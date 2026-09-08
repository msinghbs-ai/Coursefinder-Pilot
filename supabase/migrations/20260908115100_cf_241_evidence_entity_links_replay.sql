-- CF-241 — restore governed Evidence entity-link derived subsystem to migration history.
-- This relation and its maintenance helpers exist in accepted Pilot runtime truth and are
-- required by Evidence filters, Evidence related-entity views and data-quality evidence counts.

create table if not exists pipeline.evidence_entity_links (
  evidence_id uuid not null references pipeline.evidence_artifacts(id) on delete cascade,
  entity_type text not null check (entity_type in ('provider','course','campus','scholarship')),
  entity_id uuid not null,
  provider_id uuid,
  link_count bigint not null default 0 check (link_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (evidence_id,entity_type,entity_id)
);
create index if not exists evidence_entity_links_entity_idx on pipeline.evidence_entity_links(entity_type,entity_id,evidence_id);
create index if not exists evidence_entity_links_provider_idx on pipeline.evidence_entity_links(provider_id,evidence_id);

create or replace function security.evidence_row_entity_links(p_table text,p_row jsonb)
returns table(entity_type text,entity_id uuid,provider_id uuid)
language plpgsql
stable security definer
set search_path to 'pg_catalog','catalogue','scholarship'
as $function$
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
    if v_course is not null then select c.provider_id into v_provider from catalogue.courses c where c.id=v_course; return query select 'course'::text,v_course,v_provider;
    elsif v_provider is not null then return query select 'provider'::text,v_provider,v_provider; end if; return;
  elsif p_table like 'catalogue.course_%' then
    if v_course is not null then if v_provider is null then select c.provider_id into v_provider from catalogue.courses c where c.id=v_course; end if; return query select 'course'::text,v_course,v_provider; end if;
    if v_campus is not null then return query select 'campus'::text,v_campus,v_provider; end if; return;
  elsif p_table='scholarship.scholarships' then
    v_scholarship:=nullif(p_row->>'id','')::uuid; if v_scholarship is not null then return query select 'scholarship'::text,v_scholarship,v_provider; end if; return;
  elsif p_table='scholarship.scopes' then
    if v_scholarship is not null then if v_provider is null then select s.provider_id into v_provider from scholarship.scholarships s where s.id=v_scholarship; end if; return query select 'scholarship'::text,v_scholarship,v_provider; end if;
    if v_course is not null then select c.provider_id into v_provider from catalogue.courses c where c.id=v_course; return query select 'course'::text,v_course,v_provider; end if;
    if v_campus is not null then return query select 'campus'::text,v_campus,v_provider; end if;
    if nullif(p_row->>'provider_id','') is not null then return query select 'provider'::text,nullif(p_row->>'provider_id','')::uuid,nullif(p_row->>'provider_id','')::uuid; end if; return;
  elsif p_table like 'scholarship.%' then
    if v_scholarship is not null then if v_provider is null then select s.provider_id into v_provider from scholarship.scholarships s where s.id=v_scholarship; end if; return query select 'scholarship'::text,v_scholarship,v_provider; end if; return;
  end if;
  return;
end $function$;

create or replace function security.adjust_evidence_entity_link(p_evidence_id uuid,p_entity_type text,p_entity_id uuid,p_provider_id uuid,p_delta bigint)
returns void language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $function$
begin
  if p_evidence_id is null or p_entity_id is null or p_entity_type is null then return; end if;
  insert into pipeline.evidence_entity_links(evidence_id,entity_type,entity_id,provider_id,link_count,updated_at)
  values(p_evidence_id,p_entity_type,p_entity_id,p_provider_id,greatest(p_delta,0),now())
  on conflict(evidence_id,entity_type,entity_id) do update set provider_id=coalesce(excluded.provider_id,pipeline.evidence_entity_links.provider_id),link_count=greatest(0,pipeline.evidence_entity_links.link_count+p_delta),updated_at=now();
  delete from pipeline.evidence_entity_links where evidence_id=p_evidence_id and entity_type=p_entity_type and entity_id=p_entity_id and link_count=0;
end $function$;

create or replace function security.sync_evidence_entity_links()
returns trigger language plpgsql security definer set search_path to 'pg_catalog','security' as $function$
declare v_old jsonb; v_new jsonb; v_evidence uuid; r record; v_table text:=tg_table_schema||'.'||tg_table_name;
begin
  if tg_op in ('UPDATE','DELETE') then v_old:=to_jsonb(old); v_evidence:=nullif(v_old->>'evidence_id','')::uuid; if v_evidence is not null then for r in select * from security.evidence_row_entity_links(v_table,v_old) loop perform security.adjust_evidence_entity_link(v_evidence,r.entity_type,r.entity_id,r.provider_id,-1); end loop; end if; end if;
  if tg_op in ('INSERT','UPDATE') then v_new:=to_jsonb(new); v_evidence:=nullif(v_new->>'evidence_id','')::uuid; if v_evidence is not null then for r in select * from security.evidence_row_entity_links(v_table,v_new) loop perform security.adjust_evidence_entity_link(v_evidence,r.entity_type,r.entity_id,r.provider_id,1); end loop; end if; end if;
  return case when tg_op='DELETE' then old else new end;
end $function$;

revoke all on function security.adjust_evidence_entity_link(uuid,text,uuid,uuid,bigint) from public,anon,authenticated;
revoke all on function security.sync_evidence_entity_links() from public,anon,authenticated;

do $$
declare
  v_rel text;
  v_links record;
  v_relations text[]:=array[
    'catalogue.campuses','catalogue.course_academic_options','catalogue.course_campuses','catalogue.course_collection_memberships','catalogue.course_english_requirements','catalogue.course_fees','catalogue.course_field_observations','catalogue.course_identifiers','catalogue.course_intakes','catalogue.course_links','catalogue.course_registrations','catalogue.course_regulatory_observations','catalogue.course_study_level_observations','catalogue.provider_associations','catalogue.provider_collection_memberships','catalogue.provider_identifiers','catalogue.provider_outcomes','catalogue.provider_rankings','catalogue.provider_registrations','catalogue.student_flow_observations','scholarship.application_windows','scholarship.award_tiers','scholarship.coverage','scholarship.criteria','scholarship.criterion_groups','scholarship.identifiers','scholarship.offering_cycles','scholarship.scholarships','scholarship.scopes'
  ];
begin
  foreach v_rel in array v_relations loop if to_regclass(v_rel) is not null then execute format('lock table %s in share row exclusive mode',v_rel); end if; end loop;
  if not exists(select 1 from pipeline.evidence_entity_links) then
    foreach v_rel in array v_relations loop
      if to_regclass(v_rel) is not null and exists(select 1 from pg_attribute where attrelid=to_regclass(v_rel) and attname='evidence_id' and attnum>0 and not attisdropped) then
        for v_links in execute format('select t.evidence_id, x.entity_type, x.entity_id, x.provider_id from %s t cross join lateral security.evidence_row_entity_links(%L,to_jsonb(t)) x where t.evidence_id is not null and x.entity_id is not null',v_rel,v_rel)
        loop
          perform security.adjust_evidence_entity_link(v_links.evidence_id,v_links.entity_type,v_links.entity_id,v_links.provider_id,1);
        end loop;
      end if;
    end loop;
  end if;
  foreach v_rel in array v_relations loop
    if to_regclass(v_rel) is not null and exists(select 1 from pg_attribute where attrelid=to_regclass(v_rel) and attname='evidence_id' and attnum>0 and not attisdropped) and not exists(select 1 from pg_trigger where tgrelid=to_regclass(v_rel) and tgname='evidence_entity_links_sync' and not tgisinternal) then
      execute format('create trigger evidence_entity_links_sync after insert or delete or update on %s for each row execute function security.sync_evidence_entity_links()',v_rel);
    end if;
  end loop;
end $$;

comment on table pipeline.evidence_entity_links is 'Derived governed Evidence-to-entity link cache restored to migration history by CF-241.';
