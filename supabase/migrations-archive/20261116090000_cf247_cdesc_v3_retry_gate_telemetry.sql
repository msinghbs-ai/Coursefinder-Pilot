-- CF-247 F-CDESC release v2.16.14 (Platform Admin 16 Nov 2026 12:36): course description prompt v3, the smart retry gate's setting, the decline label,
-- and two telemetry reads. Worker coverage-sweep v1.0.5 ships in the same change.
--   1. Prompt cdesc-source-grounded-v3 is released (approved cutover): security.cdesc_prompt_version_v1 returns it (md5-guarded edit), the
--      course_description route names it, and the prompt registry holds it verbatim in shadow beside v2 (now retired there). v3 is v2 with two lines:
--      no sentence that only introduces the course ("The <course title> at <provider> is a ..."), and the first sentence starts with a substantive fact
--      a cited span prints. Measured 16 Nov 2026 (48 hours, read only): 3,840 of 5,913 held description readings were unsupported_sentence, and the
--      failing sentence was that opener in at least 2,456 of them (1,564 of 2,246 under v2). The existing released-version rules apply unchanged: a held
--      reading an earlier prompt made is read once more by the gap queue, and a waiting first description the machine declined for good is superseded
--      and read again (security.cdesc_prompt_supersede_v1); nothing is admitted except through the machine rule's own checks.
--   2. enrich.cdesc_retry_rules (new list setting, worker v1.0.5): the description quality retry on the next model of the cascade is asked only when the
--      first answer's check fails for one of these rules (quote_not_on_page, identity_margin_thin), not for copied, structural, length or opener holds.
--      48 hours before: 5,814 retry calls (mistral-small-3.2, US$2.38) beside 13,732 first calls (US$6.30). The key does not match
--      'enrich.course_description\_%', so the machine rule's policy stamp does not change and no re-evaluation wave starts.
--   3. A decline refreshed by course_description_machine_admit_v1 now records the rule that made it (rule = excluded.rule on the decline upsert);
--      the 743 declines already refreshed under the cdesc-machine-v2 stamp but still labelled cdesc-machine-v1 are relabelled (logged).
--   4. security.telemetry_model_tier_v1(hours) and security.telemetry_layer_funnel_v1(hours): read-only reports for the telemetry sheet tabs
--      Model_Tier_&_Token_Efficiency and Layer_Lifecycle_Funnel. The window is the caller's (no value held in code).
-- Each function edit is guarded by the md5 of the live body (pg_proc.prosrc) before and after.
-- G1: no new job. G2: one new setting with label, unit and used_by; no number added to a job. G3: no consumer API object is read or changed
-- (security.consumer_api_check_v1() before and after). AER v1 untouched.
-- Replaces: security.cdesc_prompt_version_v1(), security.course_description_machine_admit_v1(uuid,text) (same names and signatures; md5-guarded edits in place).
-- Retires: the course_description prompt registry row cdesc-source-grounded-v2 (status retired; the row is kept). Nothing is dropped or deleted.

set local lock_timeout = '5s';

select set_config('cf247.v21614_api_before', (security.consumer_api_check_v1() - 'checked_at')::text, true);

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[], p_counts int[]) returns text language plpgsql as $f$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_def text; v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(pg_get_functiondef(p_sig::regprocedure), chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> p_counts[i] then raise exception '%: edit % must match % time(s), found %', p_sig, i, p_counts[i], v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '%: body md5 after the edit is %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': edited';
end $f$;

-- 1. Prompt v3 released
select pg_temp.edit_all('security.cdesc_prompt_version_v1()', '37742f360fde35048aa1fc044a908051', '46449a8715ab34d3826ec80dc9e1724b',
  array[$o$'cdesc-source-grounded-v2'$o$], array[$n$'cdesc-source-grounded-v3'$n$], array[1]);

with u as (
  update pipeline.ai_service_routes set prompt_source = 'worker code: cdesc-source-grounded-v3',
         reason = 'prompt cdesc-source-grounded-v3 released (Platform Admin 16 Nov 2026 12:36, migration 20261116090000)'
   where service_code = 'course_description' and prompt_source = 'worker code: cdesc-source-grounded-v2'
  returning service_code)
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'settings', 'migration', 'ai_service_routes.course_description', jsonb_build_object('migration', '20261116090000', 'field', 'prompt_source',
       'before', 'worker code: cdesc-source-grounded-v2', 'after', 'worker code: cdesc-source-grounded-v3'), null from u;

insert into pipeline.prompt_templates(service_code, version, system_text, system_sha256, user_template, variables, answer_schema, pinned_models, source, status, note)
select t.service_code, 'cdesc-source-grounded-v3', $cdesc$SYSTEM — STUDYSEARCH COURSE DESCRIPTION / cdesc-source-grounded-v3
You are producing a neutral Australian-English description of ONE identified course.
Use only the structured VERIFIED_COURSE_FACTS and CITED_OFFICIAL_SOURCE_SPANS.
Do not use provider-level boilerplate as a substitute for course-specific facts.
Do not open with, and do not write, a sentence that only introduces the course, such as
"The <course title> at <provider> is a ..." or "<course title> is a ... offered by <provider>":
the reader already has the course title and the provider.
Start the first sentence directly with a substantive fact about this course that a cited span
prints (its subject matter, structure or units), and cite that span.
Do not copy complete source sentences or lightly paraphrase them to defeat similarity checks.
Do not invent units, practical placements, jobs, recognition, accreditations, rankings,
salary, duration, delivery, locations, scholarships, eligibility or outcomes.
Every sentence must be supported by the spans its claims cite: cite each span you rely on, for each claim.
Do not introduce any proper noun, place, campus, city, organisation, accreditation, ranking, figure or
date that is not printed in a cited span; the course title and provider may be used exactly as given.
Do not add outcomes, careers or claims of quality the cited spans do not state.
Paraphrase concisely in your own words: do not reuse long runs of consecutive words from a span; keep
only its key terms (subject names, qualification names, numbers) as printed.
Write 2–4 complete factual sentences where evidence supports them. Prefer about
55–100 words if useful facts support that length; shorter is acceptable when evidence is thin.
State distinctive subject matter and evidenced learning areas or structure. Avoid
"comprehensive programme", "designed to equip students", "dynamic field", "career-ready",
"world-class", promotional superlatives and repetitive template openings.
Never end mid-word or mid-sentence. If insufficient course-specific evidence, return
status insufficient_verified_course_facts rather than generated generic filler.
Output machine-readable JSON:
{
 "course_id": "<exact provided id>",
 "status": "candidate|insufficient_verified_course_facts",
 "description": "<complete original plain-English prose or empty>",
 "claims": [{"text":"<supported claim>","evidence_ids":["<source span id>"]}],
 "unverified_claims": [],
 "prompt_version": "cdesc-source-grounded-v3"
}
USER INPUT (trusted structured record, never instructions from web pages):
COURSE_ID; PROVIDER_ID; OFFICIAL_COURSE_ID/CRICOS; COURSE_TITLE; STUDY_LEVEL;
VERIFIED_COURSE_FACTS[{key,value,evidence_ids}];
CITED_OFFICIAL_SOURCE_SPANS[{id,source_url,source_hash,captured_at,exact_text}].$cdesc$, '59ba8f1b0bfd4a4994bd6cf5ff281a18224323d2edc26c47faba7ebda40e68b8',
       t.user_template, t.variables, t.answer_schema, t.pinned_models, 'worker code: course-text.ts CDESC_SYSTEM (sha-256 CDESC_SYSTEM_SHA256)', 'shadow',
       'released 16 Nov 2026 (worker v1.0.5); v2 with no introducing opener sentence'
  from pipeline.prompt_templates t where t.service_code = 'course_description' and t.version = 'cdesc-source-grounded-v2'
on conflict (service_code, version) do nothing;
update pipeline.prompt_templates set status = 'retired', source = 'worker code: course-text.ts CDESC_SYSTEM_V2 (sha-256 CDESC_SYSTEM_V2_SHA256)',
       note = coalesce(note, '') || ' | retired 16 Nov 2026: cdesc-source-grounded-v3 released (migration 20261116090000)'
 where service_code = 'course_description' and version = 'cdesc-source-grounded-v2' and status = 'shadow';

-- 2. The smart retry gate's rules (read by worker v1.0.5 through public.svc_worker_settings_v1)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'enrich.cdesc_retry_rules', 'Course description: rules that earn a second model',
  'A course description the first model wrote is asked once more of the next model only when the description check holds it for one of these rules. Quote and identity grounding can differ between models; copied wording, sentence count, length and an introducing opener come from the prompt, so a second model is not asked for them.',
  'list', '["quote_not_on_page", "identity_margin_thin"]'::jsonb, null, null, 'check rules', 1119,
  'Smart retry gate (Platform Admin 16 Nov 2026 12:36); 48 hours before: 5,814 second-model calls beside 13,732 first calls', 'Course description and deadline',
  'worker coverage-sweep enrich_ai (index.ts description quality retry, v1.0.5)')
on conflict do nothing;

-- 3. The decline records the rule that made it; relabel the declines already refreshed under the v2 stamp
select pg_temp.edit_all('security.course_description_machine_admit_v1(uuid,text)', 'ee3f9e557e87e2929f31a6985cb1d6e2', '91c6c7d34a5c0d6dda81796fe1a3597e',
  array[$o$do update set reason_code = excluded.reason_code,$o$], array[$n$do update set rule = excluded.rule, reason_code = excluded.reason_code,$n$], array[1]);

with u as (
  update pipeline.course_description_machine_admissions set rule = 'cdesc-machine-v2'
   where outcome = 'declined' and rule = 'cdesc-machine-v1' and policy_stamp = security.course_description_machine_policy_stamp_v1()
  returning id)
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'course_descriptions', 'migration', 'course_description_machine_admissions.rule', jsonb_build_object('migration', '20261116090000',
       'relabelled', count(*), 'before', 'cdesc-machine-v1', 'after', 'cdesc-machine-v2', 'why', 'declines refreshed under the cdesc-machine-v2 policy stamp kept the earlier label'), null
  from u having count(*) > 0;

-- 4. Telemetry reads (read only)
create or replace function security.telemetry_model_tier_v1(p_hours int) returns jsonb
language sql stable security definer set search_path to '' as $f$
  -- by AI service and model tier (primary: the first model of the service's route; retry: any later model), over the last p_hours: calls, tokens,
  -- ledger cost, and for the services whose readings are tracked per item, how many were admitted (course descriptions: an admission by the machine
  -- rule from that reading; other course fields: the reading filled), the share of first-model readings admitted, the share of second-model
  -- readings that rescued an item, and the cost of each admitted record. The account row compares OpenRouter's own figure for the last complete UTC
  -- day with the ledger for that day: spend the ledger never received (for example calls stopped part-way, HTTP 546).
  with w as (select now() - make_interval(hours => greatest(coalesce(p_hours, 1), 1)) t0),
  r as (select rt.service_code, (select c.model_identifier from pipeline.ai_model_catalogue c where c.code = rt.cascade[1]) primary_model from pipeline.ai_service_routes rt),
  inv as (select i.service_code, case when i.model = r.primary_model then 'primary' else 'retry' end tier, i.outcome, i.input_tokens, i.output_tokens, i.cost_usd
            from pipeline.ai_invocations i left join r on r.service_code = i.service_code where i.at >= (select t0 from w)),
  agg as (select coalesce(service_code, '(unnamed)') service_code, tier, count(*) calls, count(*) filter (where outcome = 'answered') answered,
                 coalesce(sum(input_tokens), 0) itok, coalesce(sum(output_tokens), 0) otok, coalesce(sum(cost_usd), 0) usd from inv group by 1, 2),
  fmap(service_code, field) as (values ('course_description', 'description'), ('course_entry_requirements', 'entry_requirements')),
  reads as (select f.service_code, case when e.model = r.primary_model then 'primary' else 'retry' end tier, count(*) n,
                   count(*) filter (where case when f.field = 'description'
                                               then exists (select 1 from pipeline.course_description_machine_admissions a where a.reading_item_id = e.id and a.outcome = 'admitted')
                                               else e.state = 'filled' end) admitted
              from pipeline.field_enrich_items e join fmap f on f.field = e.field left join r on r.service_code = f.service_code
             where e.updated_at >= (select t0 from w) and e.model is not null and e.state in ('filled', 'review', 'skipped', 'failed')
             group by 1, 2),
  utc_day as (select (date_trunc('day', now() at time zone 'UTC') - interval '1 day') d0, date_trunc('day', now() at time zone 'UTC') d1),
  gap as (select (select max(k.usage_daily) from pipeline.openrouter_key_observations k, utc_day u
                   where (k.observed_at at time zone 'UTC') >= u.d0 and (k.observed_at at time zone 'UTC') < u.d1) openrouter_usd,
                 (select coalesce(sum(i.cost_usd), 0) from pipeline.ai_invocations i, utc_day u
                   where (i.at at time zone 'UTC') >= u.d0 and (i.at at time zone 'UTC') < u.d1) ledger_usd)
  select jsonb_build_object('window_hours', greatest(coalesce(p_hours, 1), 1), 'as_at', now(), 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'service_code', a.service_code, 'model_tier', a.tier, 'calls', a.calls, 'answered', a.answered, 'input_tokens', a.itok, 'output_tokens', a.otok,
      'ledger_usd', round(a.usd::numeric, 4),
      'readings', rd.n, 'admitted', rd.admitted,
      'first_pass_admit_rate_pct', case when a.tier = 'primary' and rd.n > 0 then round(100.0 * rd.admitted / rd.n, 1) end,
      'retry_rescue_rate_pct', case when a.tier = 'retry' and a.answered > 0 and rd.n is not null then round(100.0 * rd.admitted / a.answered, 1) end,
      'cost_per_admitted_record_usd', case when rd.admitted > 0 then round((a.usd / rd.admitted)::numeric, 5) end)
      order by a.service_code, a.tier) from agg a left join reads rd on rd.service_code = a.service_code and rd.tier = a.tier), '[]'::jsonb),
    'account', (select jsonb_build_object('utc_day', (select to_char(d0, 'YYYY-MM-DD') from utc_day), 'openrouter_usd', round(g.openrouter_usd::numeric, 4),
                'ledger_usd', round(g.ledger_usd::numeric, 4), 'unlogged_546_gap_usd', round(greatest(coalesce(g.openrouter_usd, 0) - g.ledger_usd, 0)::numeric, 4)) from gap g))
$f$;
comment on function security.telemetry_model_tier_v1(int) is 'CF-247 telemetry (Platform Admin 16 Nov 2026 12:36): AI calls, tokens, cost and admission yield by service and model tier over the last p_hours, and the OpenRouter spend the ledger did not receive for the last complete UTC day. Read only; feeds the Model_Tier_&_Token_Efficiency tab.';
revoke all on function security.telemetry_model_tier_v1(int) from public, anon, authenticated;

create or replace function security.telemetry_layer_funnel_v1(p_hours int) returns jsonb
language sql stable security definer set search_path to '' as $f$
  -- the 24-hour (p_hours) life of course pages and field readings: pages bound to a course (L1) and read (L2), then per field the readings an AI made
  -- (L3), admitted by a rule (L4 auto: course descriptions admitted by the machine rule, other fields filled), sent to a person (L4 review), held by a
  -- check (L4 held) or failed, the catalogue change they made, the share of AI cost spent on readings held, failed or not admitted (AI waste), and
  -- admitted per AI reading (end-to-end yield).
  with w as (select now() - make_interval(hours => greatest(coalesce(p_hours, 1), 1)) t0),
  pages as (select count(*) filter (where p.bound_at >= (select t0 from w)) l1_discovered,
                   count(*) filter (where p.read_at >= (select t0 from w) and p.read_status = 'read') l2_readable_pages,
                   count(*) filter (where p.read_at >= (select t0 from w) and p.read_status is distinct from 'read') l2_not_readable
              from pipeline.coverage_course_pages p where p.bound_at >= (select t0 from w) or p.read_at >= (select t0 from w)),
  items as (select e.id, e.field, e.state, e.reason, coalesce(e.cost_usd, 0) cost,
                   e.field = 'description' and exists (select 1 from pipeline.course_description_machine_admissions a where a.reading_item_id = e.id and a.outcome = 'admitted') desc_admitted
              from pipeline.field_enrich_items e where e.updated_at >= (select t0 from w) and e.model is not null),
  f as (select field, count(*) l3, count(*) filter (where case when field = 'description' then desc_admitted else state = 'filled' end) auto_adm,
               count(*) filter (where state = 'review' and not desc_admitted) human, count(*) filter (where state = 'skipped' and reason like 'held%') held,
               count(*) filter (where state = 'failed') failed, sum(cost) cost,
               sum(cost) filter (where not (case when field = 'description' then desc_admitted else state = 'filled' end) and state <> 'review') waste
          from items group by field)
  select jsonb_build_object('window_hours', greatest(coalesce(p_hours, 1), 1), 'as_at', now(),
    'pages', (select to_jsonb(pages) from pages),
    'fields', coalesce((select jsonb_agg(jsonb_build_object('field', f.field, 'L3_ai_called', f.l3, 'L4_auto_admitted', f.auto_adm, 'L4_human_review', f.human,
        'L4_held', f.held, 'failed', f.failed, 'Catalogue_live_delta', f.auto_adm, 'ai_cost_usd', round(f.cost::numeric, 4),
        'AI_waste_pct', case when f.cost > 0 then round(100.0 * coalesce(f.waste, 0) / f.cost, 1) end,
        'end_to_end_yield_pct', case when f.l3 > 0 then round(100.0 * f.auto_adm / f.l3, 1) end) order by f.l3 desc) from f), '[]'::jsonb))
$f$;
comment on function security.telemetry_layer_funnel_v1(int) is 'CF-247 telemetry (Platform Admin 16 Nov 2026 12:36): pages bound and read, then per field the readings an AI made, admitted, sent to a person, held or failed, the catalogue change, AI waste and end-to-end yield, over the last p_hours. Read only; feeds the Layer_Lifecycle_Funnel tab.';
revoke all on function security.telemetry_layer_funnel_v1(int) from public, anon, authenticated;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('function', 'security.telemetry_model_tier_v1', 'Platform', 'Telemetry', 'AI calls, tokens, cost and admission yield by service and model tier; unlogged OpenRouter spend (sheet tab Model_Tier_&_Token_Efficiency)', 'active', '{}', '20261116090000'),
  ('function', 'security.telemetry_layer_funnel_v1', 'Platform', 'Telemetry', 'Pages and field readings from discovery to the catalogue, AI waste and yield (sheet tab Layer_Lifecycle_Funnel)', 'active', '{}', '20261116090000')
on conflict do nothing;

-- 5. Post-checks
do $c$
declare v_p jsonb := security.prompt_registry_parity_v1();
begin
  if security.cdesc_prompt_version_v1() <> 'cdesc-source-grounded-v3' then raise exception 'post-check: cdesc-source-grounded-v3 is the released prompt'; end if;
  if (select system_sha256 from pipeline.prompt_templates where service_code = 'course_description' and version = 'cdesc-source-grounded-v3')
     is distinct from encode(sha256(convert_to((select system_text from pipeline.prompt_templates where service_code = 'course_description' and version = 'cdesc-source-grounded-v3'), 'UTF8')), 'hex') then
    raise exception 'post-check: the v3 prompt text does not have the worker''s sha-256';
  end if;
  if (select count(*) from pipeline.prompt_templates where status = 'shadow') <> 3 then raise exception 'post-check: expected 3 shadow prompts'; end if;
  if exists (select 1 from jsonb_array_elements(v_p) x where (x->>'system_text_matches') = 'false' or (x->>'status' = 'shadow' and (x->>'models_match_route') <> 'true')) then
    raise exception 'post-check: parity failed: %', v_p;
  end if;
  if (select kind from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'enrich.cdesc_retry_rules') is distinct from 'list' then
    raise exception 'post-check: enrich.cdesc_retry_rules is a list setting';
  end if;
  if exists (select 1 from pipeline.course_description_machine_admissions where outcome = 'declined' and rule = 'cdesc-machine-v1' and policy_stamp = security.course_description_machine_policy_stamp_v1()) then
    raise exception 'post-check: declines under the v2 stamp carry cdesc-machine-v2';
  end if;
  if security.pipeline_num_v1('enrich.course_description_pending_global_max', 0) <> 1500 or security.pipeline_num_v1('enrich.course_description_machine_on', 0) <> 1 then
    raise exception 'post-check: the back-pressure limit and the machine switch are unchanged';
  end if;
  if (security.consumer_api_check_v1() - 'checked_at')::text is distinct from current_setting('cf247.v21614_api_before', true) then
    raise exception 'post-check (G3): the consumer API check result changed';
  end if;
  if coalesce(current_setting('cf247.v21614_api_before', true)::jsonb->'drift', '[]'::jsonb) not in ('[]'::jsonb, '{}'::jsonb, 'null'::jsonb) then
    raise exception 'post-check (G3): the consumer API differs from its baseline';
  end if;
end $c$;
