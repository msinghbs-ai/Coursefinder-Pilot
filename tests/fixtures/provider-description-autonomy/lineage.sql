-- Guards: Provider Description mandate §8–9: exact production lineage dependency schema/code metadata, no production data.
create table pipeline.evidence_entity_links (
  evidence_id uuid not null,
  entity_type text not null,
  entity_id uuid not null,
  provider_id uuid,
  link_count bigint default 0 not null,
  updated_at timestamp with time zone default now() not null
);
alter table pipeline.evidence_entity_links add constraint evidence_entity_links_entity_type_check CHECK ((entity_type = ANY (ARRAY['provider'::text, 'course'::text, 'campus'::text, 'scholarship'::text])));
alter table pipeline.evidence_entity_links add constraint evidence_entity_links_evidence_id_fkey FOREIGN KEY (evidence_id) REFERENCES pipeline.evidence_artifacts(id) ON DELETE CASCADE;
alter table pipeline.evidence_entity_links add constraint evidence_entity_links_link_count_check CHECK ((link_count >= 0));
alter table pipeline.evidence_entity_links add constraint evidence_entity_links_pkey PRIMARY KEY (evidence_id, entity_type, entity_id);
revoke all on pipeline.evidence_entity_links from public,anon,authenticated,service_role;
CREATE INDEX evidence_entity_links_entity_idx ON pipeline.evidence_entity_links USING btree (entity_type, entity_id, evidence_id);
create table pipeline.evidence_lineage_stats (
  evidence_id uuid not null,
  observation_count bigint default 0 not null,
  source_null_count bigint default 0 not null,
  rejected_count bigint default 0 not null,
  updated_at timestamp with time zone default now() not null
);
alter table pipeline.evidence_lineage_stats add constraint evidence_lineage_stats_evidence_id_fkey FOREIGN KEY (evidence_id) REFERENCES pipeline.evidence_artifacts(id) ON DELETE CASCADE;
alter table pipeline.evidence_lineage_stats add constraint evidence_lineage_stats_observation_count_check CHECK ((observation_count >= 0));
alter table pipeline.evidence_lineage_stats add constraint evidence_lineage_stats_pkey PRIMARY KEY (evidence_id);
alter table pipeline.evidence_lineage_stats add constraint evidence_lineage_stats_rejected_count_check CHECK ((rejected_count >= 0));
alter table pipeline.evidence_lineage_stats add constraint evidence_lineage_stats_source_null_count_check CHECK ((source_null_count >= 0));
revoke all on pipeline.evidence_lineage_stats from public,anon,authenticated,service_role;
set check_function_bodies=off;
CREATE OR REPLACE FUNCTION security.sync_evidence_lineage_stats()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security'
AS $function$
declare
  v_old jsonb;
  v_new jsonb;
  v_old_evidence uuid;
  v_new_evidence uuid;
  v_table text:=tg_table_schema||'.'||tg_table_name;
begin
  if tg_op in ('UPDATE','DELETE') then
    v_old:=to_jsonb(old);
    v_old_evidence:=nullif(v_old->>'evidence_id','')::uuid;
    perform security.adjust_evidence_lineage_stats(
      v_old_evidence,
      -1,
      case when security.evidence_row_source_null(v_table,v_old) then -1 else 0 end,
      case when security.evidence_row_rejected(v_old) then -1 else 0 end
    );
  end if;
  if tg_op in ('INSERT','UPDATE') then
    v_new:=to_jsonb(new);
    v_new_evidence:=nullif(v_new->>'evidence_id','')::uuid;
    perform security.adjust_evidence_lineage_stats(
      v_new_evidence,
      1,
      case when security.evidence_row_source_null(v_table,v_new) then 1 else 0 end,
      case when security.evidence_row_rejected(v_new) then 1 else 0 end
    );
  end if;
  return case when tg_op='DELETE' then old else new end;
end
$function$;
revoke all on function security.sync_evidence_lineage_stats() from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION security.sync_evidence_entity_links()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security'
AS $function$
declare v_old jsonb; v_new jsonb; v_evidence uuid; r record; v_table text:=tg_table_schema||'.'||tg_table_name;
begin
  if tg_op in ('UPDATE','DELETE') then v_old:=to_jsonb(old); v_evidence:=nullif(v_old->>'evidence_id','')::uuid; if v_evidence is not null then for r in select * from security.evidence_row_entity_links(v_table,v_old) loop perform security.adjust_evidence_entity_link(v_evidence,r.entity_type,r.entity_id,r.provider_id,-1); end loop; end if; end if;
  if tg_op in ('INSERT','UPDATE') then v_new:=to_jsonb(new); v_evidence:=nullif(v_new->>'evidence_id','')::uuid; if v_evidence is not null then for r in select * from security.evidence_row_entity_links(v_table,v_new) loop perform security.adjust_evidence_entity_link(v_evidence,r.entity_type,r.entity_id,r.provider_id,1); end loop; end if; end if;
  return case when tg_op='DELETE' then old else new end;
end $function$;
revoke all on function security.sync_evidence_entity_links() from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION security.evidence_row_source_null(p_table text, p_row jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
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
end
$function$;
revoke all on function security.evidence_row_source_null(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function security.evidence_row_source_null(text,jsonb) to public;
CREATE OR REPLACE FUNCTION security.evidence_row_rejected(p_row jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select lower(coalesce(p_row->>'status',p_row->>'lifecycle_status',''))='rejected'
$function$;
revoke all on function security.evidence_row_rejected(jsonb) from public,anon,authenticated,service_role;
grant execute on function security.evidence_row_rejected(jsonb) to public;
CREATE OR REPLACE FUNCTION security.evidence_row_entity_links(p_table text, p_row jsonb)
 RETURNS TABLE(entity_type text, entity_id uuid, provider_id uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'scholarship'
AS $function$
declare v_course uuid; v_provider uuid; v_campus uuid; v_scholarship uuid;
begin
  v_course:=nullif(p_row->>'course_id','')::uuid; v_provider:=nullif(p_row->>'provider_id','')::uuid; v_campus:=nullif(p_row->>'campus_id','')::uuid; v_scholarship:=nullif(p_row->>'scholarship_id','')::uuid;
  if p_table='catalogue.campuses' then return query select 'campus'::text,nullif(p_row->>'id','')::uuid,v_provider; return;
  elsif p_table='catalogue.provider_associations' then return query select 'provider'::text,nullif(p_row->>'from_provider_id','')::uuid,nullif(p_row->>'from_provider_id','')::uuid; return query select 'provider'::text,nullif(p_row->>'to_provider_id','')::uuid,nullif(p_row->>'to_provider_id','')::uuid; return;
  elsif p_table like 'catalogue.provider_%' then if v_provider is not null then return query select 'provider'::text,v_provider,v_provider; end if; return;
  elsif p_table='catalogue.student_flow_observations' then if v_course is not null then select c.provider_id into v_provider from catalogue.courses c where c.id=v_course; return query select 'course'::text,v_course,v_provider; elsif v_provider is not null then return query select 'provider'::text,v_provider,v_provider; end if; return;
  elsif p_table like 'catalogue.course_%' then if v_course is not null then if v_provider is null then select c.provider_id into v_provider from catalogue.courses c where c.id=v_course; end if; return query select 'course'::text,v_course,v_provider; end if; if v_campus is not null then return query select 'campus'::text,v_campus,v_provider; end if; return;
  elsif p_table='scholarship.scholarships' then v_scholarship:=nullif(p_row->>'id','')::uuid; if v_scholarship is not null then return query select 'scholarship'::text,v_scholarship,v_provider; end if; return;
  elsif p_table='scholarship.scopes' then if v_scholarship is not null then if v_provider is null then select s.provider_id into v_provider from scholarship.scholarships s where s.id=v_scholarship; end if; return query select 'scholarship'::text,v_scholarship,v_provider; end if; if v_course is not null then select c.provider_id into v_provider from catalogue.courses c where c.id=v_course; return query select 'course'::text,v_course,v_provider; end if; if v_campus is not null then return query select 'campus'::text,v_campus,v_provider; end if; if nullif(p_row->>'provider_id','') is not null then return query select 'provider'::text,nullif(p_row->>'provider_id','')::uuid,nullif(p_row->>'provider_id','')::uuid; end if; return;
  elsif p_table like 'scholarship.%' then if v_scholarship is not null then if v_provider is null then select s.provider_id into v_provider from scholarship.scholarships s where s.id=v_scholarship; end if; return query select 'scholarship'::text,v_scholarship,v_provider; end if; return;
  end if; return;
end $function$;
revoke all on function security.evidence_row_entity_links(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function security.evidence_row_entity_links(text,jsonb) to authenticated;
grant execute on function security.evidence_row_entity_links(text,jsonb) to service_role;
CREATE OR REPLACE FUNCTION security.adjust_evidence_lineage_stats(p_evidence_id uuid, p_observation_delta bigint, p_source_null_delta bigint, p_rejected_delta bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
begin
  if p_evidence_id is null then return; end if;
  insert into pipeline.evidence_lineage_stats(evidence_id,observation_count,source_null_count,rejected_count,updated_at)
  values(p_evidence_id,greatest(p_observation_delta,0),greatest(p_source_null_delta,0),greatest(p_rejected_delta,0),now())
  on conflict(evidence_id) do update set
    observation_count=greatest(0,pipeline.evidence_lineage_stats.observation_count+p_observation_delta),
    source_null_count=greatest(0,pipeline.evidence_lineage_stats.source_null_count+p_source_null_delta),
    rejected_count=greatest(0,pipeline.evidence_lineage_stats.rejected_count+p_rejected_delta),
    updated_at=now();
end
$function$;
revoke all on function security.adjust_evidence_lineage_stats(uuid,bigint,bigint,bigint) from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION security.adjust_evidence_entity_link(p_evidence_id uuid, p_entity_type text, p_entity_id uuid, p_provider_id uuid, p_delta bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
begin
  if p_evidence_id is null or p_entity_id is null or p_entity_type is null then return; end if;
  insert into pipeline.evidence_entity_links(evidence_id,entity_type,entity_id,provider_id,link_count,updated_at)
  values(p_evidence_id,p_entity_type,p_entity_id,p_provider_id,greatest(p_delta,0),now())
  on conflict(evidence_id,entity_type,entity_id) do update set provider_id=coalesce(excluded.provider_id,pipeline.evidence_entity_links.provider_id),link_count=greatest(0,pipeline.evidence_entity_links.link_count+p_delta),updated_at=now();
  delete from pipeline.evidence_entity_links where evidence_id=p_evidence_id and entity_type=p_entity_type and entity_id=p_entity_id and link_count=0;
end $function$;
revoke all on function security.adjust_evidence_entity_link(uuid,text,uuid,uuid,bigint) from public,anon,authenticated,service_role;
reset check_function_bodies;
