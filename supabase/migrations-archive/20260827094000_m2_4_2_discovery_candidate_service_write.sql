-- CF-CHG-20260827-044 / M2.4.2
create or replace function public.layer2_discovery_candidates_write(p_rows jsonb)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline','public'
as $function$
declare v_count integer:=0;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_rows is null or jsonb_typeof(p_rows)<>'array' then raise exception 'rows array required' using errcode='22023'; end if;
  if jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>20 then raise exception 'candidate row count must be 1..20' using errcode='22023'; end if;
  insert into pipeline.layer2_course_discovery_candidates(trial_course_id,course_id,source_profile_version_id,provider_attempt_id,evidence_id,discovered_url,discovered_title,discovered_regulatory_code,match_score,match_basis,status,selected,blocker)
  select x.trial_course_id,x.course_id,x.source_profile_version_id,x.provider_attempt_id,x.evidence_id,x.discovered_url,x.discovered_title,x.discovered_regulatory_code,x.match_score,coalesce(x.match_basis,'{}'::jsonb),x.status,coalesce(x.selected,false),x.blocker
  from jsonb_to_recordset(p_rows) as x(trial_course_id uuid,course_id uuid,source_profile_version_id uuid,provider_attempt_id uuid,evidence_id uuid,discovered_url text,discovered_title text,discovered_regulatory_code text,match_score numeric,match_basis jsonb,status text,selected boolean,blocker text);
  get diagnostics v_count=row_count;
  return v_count;
end
$function$;
revoke all on function public.layer2_discovery_candidates_write(jsonb) from public,anon,authenticated;
grant execute on function public.layer2_discovery_candidates_write(jsonb) to service_role;