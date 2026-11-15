-- CF-247 worker v1.0.4 throughput release (Platform Admin 15 Nov 2026 15:14; prompt v2 and its re-read approved 15:46: "Yes, v2 + re-read wave").
-- Measured on the 15 Nov recovery batch: 844 of 1,866 course description readings were held by the database's own description check
-- (unsupported_sentence 527, copied_sentence 191, sentence_count 44, quote_not_on_page 32, unsupported_claim 18, length 16, marketing 12, duplicate 4).
--   1. The released course description prompt is cdesc-source-grounded-v2 (worker course-text.ts CDESC_SYSTEM, sha-256
--      646b53c7683709bd991187ec4f87813c197c6ddee7c9fd20bede6356f4de226f; v1 was e1fcd3e1d34d5700aa3daf14405cbc6cd97aa93f46b863e91ff0f18fc273e7c5 and is
--      kept in the worker as CDESC_SYSTEM_V1). security.cdesc_prompt_version_v1 returns the new version (md5-guarded edit), so the existing rules apply:
--      a held reading an earlier prompt made is read once more by the gap queue (security.enrich_course_text_gaps_v1; about 7,659 courses when measured,
--      within the course_description route cap and the daily ceiling), and a waiting first description the machine declined for good is superseded and
--      read again (security.cdesc_prompt_supersede_v1).
--   2. public.svc_course_description_check_v1: the worker asks the database's description check (security.course_description_check_v1, the same check
--      security.enrich_course_text_record_v1 applies) before recording, so an answer of the route's first model that would be held is asked once of the
--      next model of the course_description cascade. Read-only: it records nothing.
-- Not changed here: the entry requirement machine rule (aer-machine-v1, already on: aer.machine_mode 2), which admits complete, quote-proved course reads
-- and sends the rest to Layer 4; its one-off promotion pass over the waiting first reads was run on live with that rule (no rule change, AER v1 frozen).
-- Lock rule (#1149): no ALTER of any existing table; nothing written to pipeline.platform_toolset_settings; no route, model, cascade, cap, ceiling,
-- switch or mode changes (post-check).
-- G1: no new job. G2: no new value. G3: no consumer API object is read or changed.
-- Replaces: security.cdesc_prompt_version_v1() (same name and signature; md5-guarded edit of the live text).
-- Retires: nothing (cdesc-source-grounded-v1 is superseded by v2 through the released-version rule; its readings stay as they were made).

set local lock_timeout = '3s';

select set_config('cf247.v104_before', jsonb_build_object(
  'drain', security.pipeline_num_v1('layer4.drain_on', 0), 'md', security.pipeline_num_v1('reading.markdown_input', 0),
  'reorder', security.pipeline_num_v1('health.ai_reorder_on', 0), 'shadow', security.pipeline_num_v1('aer.v2_shadow_on', 0),
  'per_call', security.pipeline_num_v1('enrich.ai_items_per_call', 30), 'ceiling', security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14),
  'openrouter', (select t.enforcement from pipeline.platform_toolsets t where t.key = 'openrouter'),
  'routes', (select jsonb_agg(jsonb_build_array(r.service_code, r.enabled, r.cascade, r.daily_usd_cap, r.migration_state) order by r.service_code) from pipeline.ai_service_routes r))::text, false);

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_old text, p_new text) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
end $f$;

-- 1. The released course description prompt
select pg_temp.edit_once('security.cdesc_prompt_version_v1()', '5bc92e43ba09198e4ba92300db05cfbb',
  $o$  select 'cdesc-source-grounded-v1'::text$o$,
  $n$  select 'cdesc-source-grounded-v2'::text$n$);

-- 2. The description check, for the worker's quality retry (read-only)
create or replace function public.svc_course_description_check_v1(p_course uuid, p_value jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return security.course_description_check_v1(p_course, p_value);
end $function$;
revoke all on function public.svc_course_description_check_v1(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.svc_course_description_check_v1(uuid, jsonb) to service_role;

-- 3. The register
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'public.svc_course_description_check_v1', 'Layer 2', 'Course descriptions', 'The description check, asked by the worker before it records, for the one quality retry on the next model', 'active', '{}', '20261115160000')
on conflict do nothing;

-- 4. Post-checks: the version is released; no switch, setting, mode, ceiling or route moved
do $c$
declare v_before jsonb := current_setting('cf247.v104_before')::jsonb;
begin
  if security.cdesc_prompt_version_v1() <> 'cdesc-source-grounded-v2' then raise exception 'post-check: cdesc-source-grounded-v2 is the released prompt'; end if;
  if (select t.enforcement from pipeline.platform_toolsets t where t.key = 'openrouter') is distinct from v_before->>'openrouter'
     or security.pipeline_num_v1('layer4.drain_on', 0) <> (v_before->>'drain')::numeric or security.pipeline_num_v1('reading.markdown_input', 0) <> (v_before->>'md')::numeric
     or security.pipeline_num_v1('health.ai_reorder_on', 0) <> (v_before->>'reorder')::numeric or security.pipeline_num_v1('aer.v2_shadow_on', 0) <> (v_before->>'shadow')::numeric
     or security.pipeline_num_v1('enrich.ai_items_per_call', 30) <> (v_before->>'per_call')::numeric
     or security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14) <> (v_before->>'ceiling')::numeric
     or (select jsonb_agg(jsonb_build_array(r.service_code, r.enabled, r.cascade, r.daily_usd_cap, r.migration_state) order by r.service_code) from pipeline.ai_service_routes r)
        is distinct from v_before->'routes' then
    raise exception 'post-check: switches, settings, the OpenRouter mode, the ceiling and every route are unchanged';
  end if;
end $c$;
