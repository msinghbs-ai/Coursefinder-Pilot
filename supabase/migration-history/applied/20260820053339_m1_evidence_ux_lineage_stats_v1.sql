create table if not exists pipeline.evidence_lineage_stats (
  evidence_id uuid primary key references pipeline.evidence_artifacts(id) on delete cascade,
  observation_count bigint not null default 0 check (observation_count>=0),
  source_null_count bigint not null default 0 check (source_null_count>=0),
  rejected_count bigint not null default 0 check (rejected_count>=0),
  updated_at timestamptz not null default now()
);
revoke all on table pipeline.evidence_lineage_stats from public,anon,authenticated;

create or replace function security.evidence_row_source_null(p_table text,p_row jsonb)
returns boolean language plpgsql immutable set search_path=pg_catalog as $$
begin
  return case p_table
    when 'catalogue.course_fees' then (p_row->'amount') is null or jsonb_typeof(p_row->'amount')='null'
    when 'catalogue.course_intakes' then coalesce(p_row->>'intake_label','')='' and (p_row->'intake_year' is null or jsonb_typeof(p_row->'intake_year')='null') and (p_row->'start_date' is null or jsonb_typeof(p_row->'start_date')='null')
    when 'catalogue.course_english_requirements' then (p_row->'overall_score' is null or jsonb_typeof(p_row->'overall_score')='null') and coalesce(p_row->'component_scores','{}'::jsonb)='{}'::jsonb
    when 'catalogue.course_links' then coalesce(p_row->>'url','')=''
    when 'catalogue.course_registrations' then coalesce(p_row->>'registration_code','')=''
    when 'catalogue.course_study_level_observations' then coalesce(p_row->>'source_value','')=''
    when 'catalogue.course_field_observations' then coalesce(p_row->>'source_field_code','')='' and coalesce(p_row->>'source_field_name','')=''
    when 'catalogue.provider_outcomes' then (p_row->'metric_value' is null or jsonb_typeof(p_row->'metric_value')='null')
    when 'catalogue.student_flow_observations' then (p_row->'metric_value' is null or jsonb_typeof(p_row->'metric_value')='null') and coalesce((p_row->>'is_suppressed')::boolean,false)=false
    when 'scholarship.criteria' then (p_row->'value_text' is null or jsonb_typeof(p_row->'value_text')='null') and (p_row->'value_number' is null or jsonb_typeof(p_row->'value_number')='null') and (p_row->'value_codes' is null or jsonb_typeof(p_row->'value_codes')='null') and (p_row->'value_json' is null or jsonb_typeof(p_row->'value_json')='null')
    when 'scholarship.award_tiers' then (p_row->'amount' is null or jsonb_typeof(p_row->'amount')='null') and (p_row->'percentage' is null or jsonb_typeof(p_row->'percentage')='null') and (p_row->'maximum_amount' is null or jsonb_typeof(p_row->'maximum_amount')='null')
    else false
  end;
end $$;

create or replace function security.evidence_row_rejected(p_row jsonb)
returns boolean language sql immutable set search_path=pg_catalog as $$
  select lower(coalesce(p_row->>'status',p_row->>'lifecycle_status',''))='rejected'
$$;

create or replace function security.adjust_evidence_lineage_stats(p_evidence_id uuid,p_observation_delta bigint,p_source_null_delta bigint,p_rejected_delta bigint)
returns void language plpgsql volatile security definer set search_path=pg_catalog,pipeline as $$
begin
  if p_evidence_id is null then return; end if;
  insert into pipeline.evidence_lineage_stats(evidence_id,observation_count,source_null_count,rejected_count,updated_at)
  values(p_evidence_id,greatest(p_observation_delta,0),greatest(p_source_null_delta,0),greatest(p_rejected_delta,0),now())
  on conflict(evidence_id) do update set
    observation_count=greatest(0,pipeline.evidence_lineage_stats.observation_count+p_observation_delta),
    source_null_count=greatest(0,pipeline.evidence_lineage_stats.source_null_count+p_source_null_delta),
    rejected_count=greatest(0,pipeline.evidence_lineage_stats.rejected_count+p_rejected_delta),
    updated_at=now();
end $$;

create or replace function security.sync_evidence_lineage_stats()
returns trigger language plpgsql volatile security definer set search_path=pg_catalog,security as $$
declare v_old jsonb; v_new jsonb; v_old_evidence uuid; v_new_evidence uuid; v_table text:=tg_table_schema||'.'||tg_table_name;
begin
  if tg_op in ('UPDATE','DELETE') then
    v_old:=to_jsonb(old); v_old_evidence:=nullif(v_old->>'evidence_id','')::uuid;
    perform security.adjust_evidence_lineage_stats(v_old_evidence,-1,case when security.evidence_row_source_null(v_table,v_old) then -1 else 0 end,case when security.evidence_row_rejected(v_old) then -1 else 0 end);
  end if;
  if tg_op in ('INSERT','UPDATE') then
    v_new:=to_jsonb(new); v_new_evidence:=nullif(v_new->>'evidence_id','')::uuid;
    perform security.adjust_evidence_lineage_stats(v_new_evidence,1,case when security.evidence_row_source_null(v_table,v_new) then 1 else 0 end,case when security.evidence_row_rejected(v_new) then 1 else 0 end);
  end if;
  return case when tg_op='DELETE' then old else new end;
end $$;

truncate table pipeline.evidence_lineage_stats;
insert into pipeline.evidence_lineage_stats(evidence_id,observation_count,source_null_count,rejected_count,updated_at)
select evidence_id,count(*)::bigint,sum(source_null)::bigint,sum(rejected)::bigint,now()
from (
  select evidence_id,case when amount is null then 1 else 0 end source_null,case when lower(coalesce(status,''))='rejected' then 1 else 0 end rejected from catalogue.course_fees where evidence_id is not null
  union all select evidence_id,case when intake_label is null and intake_year is null and start_date is null then 1 else 0 end,case when lower(coalesce(status,''))='rejected' then 1 else 0 end from catalogue.course_intakes where evidence_id is not null
  union all select evidence_id,case when overall_score is null and coalesce(component_scores,'{}'::jsonb)='{}'::jsonb then 1 else 0 end,case when lower(coalesce(status,''))='rejected' then 1 else 0 end from catalogue.course_english_requirements where evidence_id is not null
  union all select evidence_id,case when url is null then 1 else 0 end,case when lower(coalesce(status,''))='rejected' then 1 else 0 end from catalogue.course_links where evidence_id is not null
  union all select evidence_id,case when registration_code is null then 1 else 0 end,case when lower(coalesce(status,''))='rejected' then 1 else 0 end from catalogue.course_registrations where evidence_id is not null
  union all select evidence_id,0,case when lower(coalesce(status,''))='rejected' then 1 else 0 end from catalogue.course_regulatory_observations where evidence_id is not null
  union all select evidence_id,case when source_value is null then 1 else 0 end,case when lower(coalesce(status,''))='rejected' then 1 else 0 end from catalogue.course_study_level_observations where evidence_id is not null
  union all select evidence_id,case when source_field_code is null and source_field_name is null then 1 else 0 end,case when lower(coalesce(status,''))='rejected' then 1 else 0 end from catalogue.course_field_observations where evidence_id is not null
  union all select evidence_id,0,0 from catalogue.course_campuses where evidence_id is not null
  union all select evidence_id,0,case when lower(coalesce(status,''))='rejected' then 1 else 0 end from catalogue.campuses where evidence_id is not null
  union all select evidence_id,case when metric_value is null then 1 else 0 end,case when lower(coalesce(status,''))='rejected' then 1 else 0 end from catalogue.provider_outcomes where evidence_id is not null
  union all select evidence_id,case when metric_value is null and coalesce(is_suppressed,false)=false then 1 else 0 end,case when lower(coalesce(status,''))='rejected' then 1 else 0 end from catalogue.student_flow_observations where evidence_id is not null
  union all select evidence_id,0,case when lower(coalesce(status,''))='rejected' then 1 else 0 end from catalogue.provider_registrations where evidence_id is not null
  union all select evidence_id,0,0 from catalogue.provider_identifiers where evidence_id is not null
  union all select evidence_id,0,case when lower(coalesce(lifecycle_status,''))='rejected' then 1 else 0 end from scholarship.scholarships where evidence_id is not null
  union all select evidence_id,0,case when lower(coalesce(status,''))='rejected' then 1 else 0 end from scholarship.offering_cycles where evidence_id is not null
  union all select evidence_id,0,case when lower(coalesce(status,''))='rejected' then 1 else 0 end from scholarship.application_windows where evidence_id is not null
  union all select evidence_id,0,0 from scholarship.scopes where evidence_id is not null
  union all select evidence_id,0,0 from scholarship.criterion_groups where evidence_id is not null
  union all select evidence_id,case when value_text is null and value_number is null and value_codes is null and value_json is null then 1 else 0 end,case when lower(coalesce(status,''))='rejected' then 1 else 0 end from scholarship.criteria where evidence_id is not null
  union all select evidence_id,case when amount is null and percentage is null and maximum_amount is null then 1 else 0 end,0 from scholarship.award_tiers where evidence_id is not null
  union all select evidence_id,0,0 from scholarship.coverage where evidence_id is not null
  union all select evidence_id,0,case when lower(coalesce(status,''))='rejected' then 1 else 0 end from scholarship.identifiers where evidence_id is not null
) x group by evidence_id;

do $$
declare r record;
begin
  for r in select * from (values
    ('catalogue','course_fees'),('catalogue','course_intakes'),('catalogue','course_english_requirements'),('catalogue','course_links'),('catalogue','course_registrations'),('catalogue','course_regulatory_observations'),('catalogue','course_study_level_observations'),('catalogue','course_field_observations'),('catalogue','course_campuses'),('catalogue','campuses'),('catalogue','provider_outcomes'),('catalogue','student_flow_observations'),('catalogue','provider_registrations'),('catalogue','provider_identifiers'),('scholarship','scholarships'),('scholarship','offering_cycles'),('scholarship','application_windows'),('scholarship','scopes'),('scholarship','criterion_groups'),('scholarship','criteria'),('scholarship','award_tiers'),('scholarship','coverage'),('scholarship','identifiers')
  ) as t(schema_name,table_name)
  loop
    execute format('drop trigger if exists %I on %I.%I','evidence_lineage_stats_sync',r.schema_name,r.table_name);
    execute format('create trigger %I after insert or update of evidence_id or delete on %I.%I for each row execute function security.sync_evidence_lineage_stats()','evidence_lineage_stats_sync',r.schema_name,r.table_name);
  end loop;
end $$;
