create table if not exists pipeline.evidence_entity_links (
  evidence_id uuid not null references pipeline.evidence_artifacts(id) on delete cascade,
  entity_type text not null check(entity_type in ('provider','course','campus','scholarship')),
  entity_id uuid not null,
  provider_id uuid,
  link_count bigint not null default 0 check(link_count>=0),
  updated_at timestamptz not null default now(),
  primary key(evidence_id,entity_type,entity_id)
);
create index if not exists evidence_entity_links_entity_idx on pipeline.evidence_entity_links(entity_type,entity_id,evidence_id);
create index if not exists evidence_entity_links_provider_idx on pipeline.evidence_entity_links(provider_id,evidence_id);
revoke all on table pipeline.evidence_entity_links from public,anon,authenticated;

create or replace function security.adjust_evidence_entity_link(p_evidence_id uuid,p_entity_type text,p_entity_id uuid,p_provider_id uuid,p_delta bigint)
returns void language plpgsql volatile security definer set search_path=pg_catalog,pipeline as $$
begin
  if p_evidence_id is null or p_entity_id is null or p_entity_type is null then return; end if;
  insert into pipeline.evidence_entity_links(evidence_id,entity_type,entity_id,provider_id,link_count,updated_at)
  values(p_evidence_id,p_entity_type,p_entity_id,p_provider_id,greatest(p_delta,0),now())
  on conflict(evidence_id,entity_type,entity_id) do update set
    provider_id=coalesce(excluded.provider_id,pipeline.evidence_entity_links.provider_id),
    link_count=greatest(0,pipeline.evidence_entity_links.link_count+p_delta),updated_at=now();
  delete from pipeline.evidence_entity_links where evidence_id=p_evidence_id and entity_type=p_entity_type and entity_id=p_entity_id and link_count=0;
end $$;

create or replace function security.evidence_row_entity_links(p_table text,p_row jsonb)
returns table(entity_type text,entity_id uuid,provider_id uuid)
language plpgsql stable security definer set search_path=pg_catalog,catalogue,scholarship as $$
declare v_course uuid; v_provider uuid; v_campus uuid; v_scholarship uuid;
begin
  v_course:=nullif(p_row->>'course_id','')::uuid;
  v_provider:=nullif(p_row->>'provider_id','')::uuid;
  v_campus:=nullif(p_row->>'campus_id','')::uuid;
  v_scholarship:=nullif(p_row->>'scholarship_id','')::uuid;

  if p_table='catalogue.campuses' then
    return query select 'campus'::text,nullif(p_row->>'id','')::uuid,v_provider; return;
  elsif p_table='catalogue.provider_associations' then
    return query select 'provider'::text,nullif(p_row->>'from_provider_id','')::uuid,nullif(p_row->>'from_provider_id','')::uuid;
    return query select 'provider'::text,nullif(p_row->>'to_provider_id','')::uuid,nullif(p_row->>'to_provider_id','')::uuid; return;
  elsif p_table like 'catalogue.provider_%' then
    if v_provider is not null then return query select 'provider'::text,v_provider,v_provider; end if; return;
  elsif p_table='catalogue.student_flow_observations' then
    if v_course is not null then
      select c.provider_id into v_provider from catalogue.courses c where c.id=v_course;
      return query select 'course'::text,v_course,v_provider;
    elsif v_provider is not null then
      return query select 'provider'::text,v_provider,v_provider;
    end if; return;
  elsif p_table like 'catalogue.course_%' then
    if v_course is not null then
      if v_provider is null then select c.provider_id into v_provider from catalogue.courses c where c.id=v_course; end if;
      return query select 'course'::text,v_course,v_provider;
    end if;
    if v_campus is not null then return query select 'campus'::text,v_campus,v_provider; end if;
    return;
  elsif p_table='scholarship.scholarships' then
    v_scholarship:=nullif(p_row->>'id','')::uuid;
    if v_scholarship is not null then return query select 'scholarship'::text,v_scholarship,v_provider; end if; return;
  elsif p_table='scholarship.scopes' then
    if v_scholarship is not null then
      if v_provider is null then select s.provider_id into v_provider from scholarship.scholarships s where s.id=v_scholarship; end if;
      return query select 'scholarship'::text,v_scholarship,v_provider;
    end if;
    if v_course is not null then
      select c.provider_id into v_provider from catalogue.courses c where c.id=v_course;
      return query select 'course'::text,v_course,v_provider;
    end if;
    if v_campus is not null then return query select 'campus'::text,v_campus,v_provider; end if;
    if nullif(p_row->>'provider_id','') is not null then
      return query select 'provider'::text,nullif(p_row->>'provider_id','')::uuid,nullif(p_row->>'provider_id','')::uuid;
    end if; return;
  elsif p_table like 'scholarship.%' then
    if v_scholarship is not null then
      if v_provider is null then select s.provider_id into v_provider from scholarship.scholarships s where s.id=v_scholarship; end if;
      return query select 'scholarship'::text,v_scholarship,v_provider;
    end if; return;
  end if;
  return;
end $$;

create or replace function security.sync_evidence_entity_links()
returns trigger language plpgsql volatile security definer set search_path=pg_catalog,security as $$
declare v_old jsonb; v_new jsonb; v_evidence uuid; r record; v_table text:=tg_table_schema||'.'||tg_table_name;
begin
  if tg_op in ('UPDATE','DELETE') then
    v_old:=to_jsonb(old); v_evidence:=nullif(v_old->>'evidence_id','')::uuid;
    if v_evidence is not null then
      for r in select * from security.evidence_row_entity_links(v_table,v_old) loop
        perform security.adjust_evidence_entity_link(v_evidence,r.entity_type,r.entity_id,r.provider_id,-1);
      end loop;
    end if;
  end if;
  if tg_op in ('INSERT','UPDATE') then
    v_new:=to_jsonb(new); v_evidence:=nullif(v_new->>'evidence_id','')::uuid;
    if v_evidence is not null then
      for r in select * from security.evidence_row_entity_links(v_table,v_new) loop
        perform security.adjust_evidence_entity_link(v_evidence,r.entity_type,r.entity_id,r.provider_id,1);
      end loop;
    end if;
  end if;
  return case when tg_op='DELETE' then old else new end;
end $$;

truncate table pipeline.evidence_entity_links;
insert into pipeline.evidence_entity_links(evidence_id,entity_type,entity_id,provider_id,link_count,updated_at)
select evidence_id,entity_type,entity_id,max(provider_id::text)::uuid provider_id,count(*)::bigint,now()
from (
  select x.evidence_id,'course'::text entity_type,x.course_id entity_id,c.provider_id from catalogue.course_fees x join catalogue.courses c on c.id=x.course_id where x.evidence_id is not null
  union all select x.evidence_id,'course',x.course_id,c.provider_id from catalogue.course_intakes x join catalogue.courses c on c.id=x.course_id where x.evidence_id is not null
  union all select x.evidence_id,'course',x.course_id,c.provider_id from catalogue.course_english_requirements x join catalogue.courses c on c.id=x.course_id where x.evidence_id is not null
  union all select x.evidence_id,'course',x.course_id,c.provider_id from catalogue.course_links x join catalogue.courses c on c.id=x.course_id where x.evidence_id is not null
  union all select x.evidence_id,'course',x.course_id,c.provider_id from catalogue.course_registrations x join catalogue.courses c on c.id=x.course_id where x.evidence_id is not null
  union all select x.evidence_id,'course',x.course_id,c.provider_id from catalogue.course_regulatory_observations x join catalogue.courses c on c.id=x.course_id where x.evidence_id is not null
  union all select x.evidence_id,'course',x.course_id,c.provider_id from catalogue.course_study_level_observations x join catalogue.courses c on c.id=x.course_id where x.evidence_id is not null
  union all select x.evidence_id,'course',x.course_id,c.provider_id from catalogue.course_field_observations x join catalogue.courses c on c.id=x.course_id where x.evidence_id is not null
  union all select x.evidence_id,'course',x.course_id,c.provider_id from catalogue.course_campuses x join catalogue.courses c on c.id=x.course_id where x.evidence_id is not null
  union all select x.evidence_id,'campus',x.campus_id,c.provider_id from catalogue.course_campuses x join catalogue.campuses c on c.id=x.campus_id where x.evidence_id is not null
  union all select x.evidence_id,'course',x.course_id,c.provider_id from catalogue.course_academic_options x join catalogue.courses c on c.id=x.course_id where x.evidence_id is not null
  union all select x.evidence_id,'course',x.course_id,c.provider_id from catalogue.course_collection_memberships x join catalogue.courses c on c.id=x.course_id where x.evidence_id is not null
  union all select x.evidence_id,'course',x.course_id,coalesce(x.provider_id,c.provider_id) from catalogue.course_identifiers x join catalogue.courses c on c.id=x.course_id where x.evidence_id is not null
  union all select x.evidence_id,'campus',x.id,x.provider_id from catalogue.campuses x where x.evidence_id is not null
  union all select x.evidence_id,'provider',x.provider_id,x.provider_id from catalogue.provider_outcomes x where x.evidence_id is not null and x.provider_id is not null
  union all select x.evidence_id,'provider',x.provider_id,x.provider_id from catalogue.provider_registrations x where x.evidence_id is not null
  union all select x.evidence_id,'provider',x.provider_id,x.provider_id from catalogue.provider_identifiers x where x.evidence_id is not null
  union all select x.evidence_id,'provider',x.provider_id,x.provider_id from catalogue.provider_rankings x where x.evidence_id is not null
  union all select x.evidence_id,'provider',x.provider_id,x.provider_id from catalogue.provider_collection_memberships x where x.evidence_id is not null
  union all select x.evidence_id,'provider',x.from_provider_id,x.from_provider_id from catalogue.provider_associations x where x.evidence_id is not null
  union all select x.evidence_id,'provider',x.to_provider_id,x.to_provider_id from catalogue.provider_associations x where x.evidence_id is not null
  union all select x.evidence_id,'course',x.course_id,c.provider_id from catalogue.student_flow_observations x join catalogue.courses c on c.id=x.course_id where x.evidence_id is not null and x.course_id is not null
  union all select x.evidence_id,'provider',x.provider_id,x.provider_id from catalogue.student_flow_observations x where x.evidence_id is not null and x.course_id is null and x.provider_id is not null
  union all select x.evidence_id,'scholarship',x.id,x.provider_id from scholarship.scholarships x where x.evidence_id is not null
  union all select x.evidence_id,'scholarship',x.scholarship_id,s.provider_id from scholarship.offering_cycles x join scholarship.scholarships s on s.id=x.scholarship_id where x.evidence_id is not null
  union all select x.evidence_id,'scholarship',x.scholarship_id,s.provider_id from scholarship.application_windows x join scholarship.scholarships s on s.id=x.scholarship_id where x.evidence_id is not null
  union all select x.evidence_id,'scholarship',x.scholarship_id,s.provider_id from scholarship.scopes x join scholarship.scholarships s on s.id=x.scholarship_id where x.evidence_id is not null
  union all select x.evidence_id,'scholarship',x.scholarship_id,s.provider_id from scholarship.criterion_groups x join scholarship.scholarships s on s.id=x.scholarship_id where x.evidence_id is not null
  union all select x.evidence_id,'scholarship',x.scholarship_id,s.provider_id from scholarship.criteria x join scholarship.scholarships s on s.id=x.scholarship_id where x.evidence_id is not null
  union all select x.evidence_id,'scholarship',x.scholarship_id,s.provider_id from scholarship.award_tiers x join scholarship.scholarships s on s.id=x.scholarship_id where x.evidence_id is not null
  union all select x.evidence_id,'scholarship',x.scholarship_id,s.provider_id from scholarship.coverage x join scholarship.scholarships s on s.id=x.scholarship_id where x.evidence_id is not null
  union all select x.evidence_id,'scholarship',x.scholarship_id,s.provider_id from scholarship.identifiers x join scholarship.scholarships s on s.id=x.scholarship_id where x.evidence_id is not null
) l where entity_id is not null group by evidence_id,entity_type,entity_id;

do $$
declare r record;
begin
  for r in select * from (values
    ('catalogue','course_fees'),('catalogue','course_intakes'),('catalogue','course_english_requirements'),('catalogue','course_links'),('catalogue','course_registrations'),
    ('catalogue','course_regulatory_observations'),('catalogue','course_study_level_observations'),('catalogue','course_field_observations'),('catalogue','course_campuses'),
    ('catalogue','course_academic_options'),('catalogue','course_collection_memberships'),('catalogue','course_identifiers'),('catalogue','campuses'),
    ('catalogue','provider_outcomes'),('catalogue','provider_registrations'),('catalogue','provider_identifiers'),('catalogue','provider_rankings'),
    ('catalogue','provider_collection_memberships'),('catalogue','provider_associations'),('catalogue','student_flow_observations'),
    ('scholarship','scholarships'),('scholarship','offering_cycles'),('scholarship','application_windows'),('scholarship','scopes'),('scholarship','criterion_groups'),
    ('scholarship','criteria'),('scholarship','award_tiers'),('scholarship','coverage'),('scholarship','identifiers')
  ) as t(schema_name,table_name)
  loop
    execute format('drop trigger if exists %I on %I.%I','evidence_entity_links_sync',r.schema_name,r.table_name);
    execute format('create trigger %I after insert or update or delete on %I.%I for each row execute function security.sync_evidence_entity_links()','evidence_entity_links_sync',r.schema_name,r.table_name);
  end loop;
end $$;
