-- CF-247 s1125 (S1-Build / Integration Controller; Platform Admin 25 Nov 2026 08:16 AEDT, P0 AER preprocessing, Admin #1063 regression cohort):
-- "Integrate the existing meaningful-content section selector into entryRead ... Verify that scheduled and on-demand processing use the same
-- existing preprocessing mechanism ... Compare selected content against the original official source evidence and the 53 previous paid AI
-- answers ... Measure actual content-size and token reduction. Qualify the most economical suitable model through the existing service
-- qualification register." No new preprocessing engine, reader, scheduler, queue or pipeline.
-- Found live (rolled back, 25 Nov 2026 08:40 AEDT):
--   * every course entry read (job aer-scheduled-read via security.aer_schedule_tick_v1, Read now via security.aer_read_now_v1 and
--     public.admin_entry_requirements, the bounded batch security.course_entry_batch_v1) enqueues pipeline.field_enrich_items through
--     security.course_entry_read_enqueue_v1 or admin_jobs enrich_fields, read by worker mode enrich_ai entryRead: one preprocessing point.
--     entryRead sends the whole page text (htmlToText without nav, header and footer) in 12,000-character slices; the section selector
--     (lean-sections-v3) runs beside it as a shadow only (reading.selection_shadow_on).
--   * route course_entry_requirements is off (Platform Admin 16 Nov 2026 16:52: Qwen3 30B 2/50 right, 18 timeouts on whole pages; 726 failed
--     attempts in 48 h); qwen3-30b and mistral-small-3.2 are unqualified for it in pipeline.ai_route_qualifications.
--   * Admin #1063 cohort (40 named AU providers of the s1108 file; identity cricos_code, adapter_code or manual; page bound; outcome
--     no_requirement_published or admitted_provider; read skipped): 225 courses, 53 with a superseded course_entry_first_read item and 152 inactive
--     rows from earlier paid Qwen3 30B answers (15 and 16 Nov), 172 never read; 3.32 M page characters.
-- What changes (live on deploy, worker v1.0.41):
--   1. reading.course_entry_sections_on (new setting, 1): entryRead sends the selector's entry-requirement blocks when it shows a likely signal,
--      otherwise the whole text (course-entry.ts courseEntryInput); the read records what it was sent (value.input). Quotes are still checked on
--      the text sent, which is the page's own words; prompt course-entry-v1 unchanged. Nothing is read while the route stays off.
--   2. The existing offline recall check (job lean-sections-eval, pipeline.lean_section_eval_cases) gets this cohort: each of the 152 earlier rows
--      as a label (gold_source ai_earlier, checked against the stored page first: an earlier answer is not ground truth) and every cohort page
--      for its sizes (gold_source cohort_size). No AI, no Firecrawl.
--   3. The existing qualification harness (job lean-qualify, pipeline.lean_qualify_cases, worker mode lean_qualify) gains the entry field: each of
--      the 53 pages (earlier answer rows) and 30 pages with rows a person accepted in Layer 4 (independent labels) is read on each of the four
--      cheapest allowed models (deepseek-v4-flash, qwen3-30b, mistral-small-3.2, mimo-v2.6-flash) with the production prompt and slicing, twice:
--      today's whole text and the selected text. Answers go to the case table only; nothing is admitted, proposed or sent to Layer 4; no route,
--      cascade or qualification changes here. Spend: the existing hard ceiling reading.lean_qualify_ceiling_usd (US$2.00) for the run, the key
--      and balance holds of the course_entry_requirements route (its off switch is what is being decided and does not stop qualification), an
--      on-demand request opened with the estimate (US$0.60). The two catalogued jobs are resumed; batch.lean_qualify 6 -> 3 pages a call.
--   4. A pass switches nothing on. Recording the outcome in the qualification register and the bounded activation stay separate steps.
--   Items 2 and 3 need the two harness CHECK constraints widened (gold_source ai_earlier and cohort_size; field entry_requirements). A migration
--   never drops a constraint (scripts/ci/apply-migration.sh), so they are replaced by the Platform Admin's paste file
--   PASTE-20261125-s1125-lean-harness-entry-labels.sql, which then calls security.lean_entry_qualify_start_v1() (this migration) to seed and start the
--   run. Renumbered from 20261126180000 (Pilot #1604), which the deploy refused for its constraint lines and which never ran.
-- G1: no new job (two catalogued jobs resumed). G2: one new setting (label, range, unit, used_by); batch and switch through the settings
--   pattern. G3: no consumer object changed (checked). Locks and cron checked (<= 140). No spending limit changed.
-- Replaces: the whole-page input of the course entry read; the shadow-only use of the section selector for it.
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '120s';  -- fixed: the consumer API check and the cohort seed

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('public.svc_lean_qualify_next_v1(integer)'::regprocedure)) <> 'b0274eab6c8fbf0061854305a7623cf2' then
    raise exception 'guard: public.svc_lean_qualify_next_v1 is not the definition this change was made from';
  end if;
end $g$;
create temp table s1125_locks on commit drop as select count(*) n from pipeline.manual_locks;

-- 1. the sections-first setting (live)
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values ('pipeline', 'reading.course_entry_sections_on', 'Course entry requirements: send the selected sections',
  '1: a course entry read sends the section selector''s entry-requirement blocks (headings, sentences, tables with their footnotes) when they show a likely signal, otherwise the whole page text; 0: always the whole page text. Quotes are checked on the text sent.',
  'number', '1'::jsonb, 0, 1, 'on (1) or off (0)', 1452,
  'Platform Admin 25 Nov 2026 08:16 AEDT (P0 AER preprocessing, Admin #1063): integrate the existing section selector into entryRead', 'Enrich fields',
  'worker coverage-sweep entryRead and lean_qualify (course-entry.ts courseEntryInput)')
on conflict (toolset_key, key) do nothing;

-- 2. the qualification table names the candidate model and the label source of an entry case (two columns added). The two harness CHECK
--    constraints that must take the entry field and the cohort labels are replaced by the Platform Admin's paste file
--    PASTE-20261125-s1125-lean-harness-entry-labels.sql (a migration never drops; scripts/ci/apply-migration.sh), which then starts the run.
alter table pipeline.lean_qualify_cases add column if not exists model_code text, add column if not exists gold_source text;
comment on column pipeline.lean_qualify_cases.model_code is 'CF-247 s1125: the candidate model (pipeline.ai_model_catalogue code) an entry_requirements case is read on; null for fees and intakes (their route''s pinned model).';
comment on column pipeline.lean_qualify_cases.gold_source is 'CF-247 s1125: where an entry_requirements case''s label rows come from: ai_earlier (an earlier paid AI answer, not ground truth) or aer_accepted (rows a person accepted in Layer 4).';

-- 3. the qualification picker hands out entry cases on their named model, under the account holds of the entry route
CREATE OR REPLACE FUNCTION public.svc_lean_qualify_next_v1(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; v_run text; v_spent numeric; v_fee jsonb := security.ai_route_v1('fee_reader'); v_int jsonb := security.ai_route_v1('course_other_fields');
  v_ent jsonb := security.ai_route_v1('course_entry_requirements');  -- CF-247 s1125: the account holds of the entry route (its off switch is what is qualified for)
  v_ent_ok boolean;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.pipeline_num_v1('reading.lean_qualify_on', 0) < 1 then return '[]'::jsonb; end if;
  -- CF-247 s1125: the newest run with pending pages (an older run's leftover page no longer blocks a newer run)
  select c.run_label into v_run from pipeline.lean_qualify_cases c where c.state = 'pending' order by c.id desc limit 1;
  v_ent_ok := coalesce((v_ent->'key'->>'held')::boolean, true) = false and coalesce((v_ent->'balance'->>'known')::boolean, false)
              and coalesce((v_ent->'balance'->>'usd')::numeric, 0) > coalesce((v_ent->'balance'->>'floor_usd')::numeric, 0);
  if v_run is null then return '[]'::jsonb; end if;
  -- the hard ceiling: nothing more is handed out once the run's recorded cost reaches it
  select coalesce(sum(c.cost_usd), 0) into v_spent from pipeline.lean_qualify_cases c where c.run_label = v_run;
  if v_spent >= security.pipeline_num_v1('reading.lean_qualify_ceiling_usd', 0) then return '[]'::jsonb; end if;
  with pick as (select c.id from pipeline.lean_qualify_cases c
                 where c.run_label = v_run and c.state = 'pending' and (c.leased_until is null or c.leased_until < now()) and c.attempts < 2  -- fixed: two tries
                   and ((c.field = 'fees' and coalesce((v_fee->>'held')::boolean, true) = false and v_fee->>'model' is not null)
                     or (c.field = 'intakes' and coalesce((v_int->>'held')::boolean, true) = false and v_int->>'model' is not null)
                     or (c.field = 'entry_requirements' and v_ent_ok and exists (select 1 from pipeline.ai_model_catalogue mc where mc.code = c.model_code and mc.status = 'allowed')))
                 order by c.id limit greatest(1, least(coalesce(p_limit, 1), 20)) for update skip locked),  -- fixed: the setting batch.lean_qualify's upper bound
  upd as (update pipeline.lean_qualify_cases c set leased_until = now() + interval '5 minutes', attempts = c.attempts + 1 from pick where c.id = pick.id  -- fixed: lease, longer than one worker call
          returning c.*)
  select coalesce(jsonb_agg(jsonb_build_object('case_id', u.id, 'field', u.field, 'kind', u.kind, 'storage_path', u.storage_path, 'gold', u.gold,
           'provider', coalesce(p.display_name, p.canonical_name), 'country', k.iso_alpha2, 'title', co.canonical_title, 'url', e.source_url,
           'profile', case when u.field = 'fees' then (select to_jsonb(cp) - 'reason' - 'updated_by' - 'updated_at' from pipeline.fee_country_profiles cp where cp.country_code = k.iso_alpha2) end,
           'courses', case when u.field = 'fees' and co.id is not null then jsonb_build_array(jsonb_build_object('id', co.id, 'title', co.canonical_title, 'level', sl.code)) else '[]'::jsonb end,
           'page_chars', case when u.field = 'entry_requirements' then security.pipeline_num_v1('entry.course_page_chars', 100000)::int else security.pipeline_num_v1('fees.page_chars', 40000)::int end,
           'model_code', u.model_code, 'gold_source', u.gold_source,
           'model', case when u.field = 'fees' then v_fee->>'model' when u.field = 'entry_requirements' then (select mc.model_identifier from pipeline.ai_model_catalogue mc where mc.code = u.model_code) else v_int->>'model' end,
           'models', case when u.field = 'fees' then v_fee->'models' when u.field = 'entry_requirements' then (select jsonb_build_array(mc.model_identifier) from pipeline.ai_model_catalogue mc where mc.code = u.model_code) else v_int->'models' end) order by u.id), '[]'::jsonb) into v
    from upd u left join catalogue.courses co on co.id = u.course_id left join ref.study_levels sl on sl.id = co.study_level_id
    left join catalogue.providers p on p.id = co.provider_id left join ref.countries k on k.id = p.country_id
    left join pipeline.evidence_artifacts e on e.id = u.evidence_id;
  return v;
end $function$
;
comment on function public.svc_lean_qualify_next_v1(integer) is 'CF-247 Lean AI Input qualification (worker mode lean_qualify): leases pending pages of the newest run with their label, course context and model, while reading.lean_qualify_on is 1 and the run''s recorded cost is below reading.lean_qualify_ceiling_usd. Fees and intakes on their route''s pinned model while the route is not held; entry_requirements (s1125) on its named allowed catalogue model while the course_entry_requirements key and balance are not held.';

-- 4. the run, started by security.lean_entry_qualify_start_v1(): the cohort (Admin #1063 conditions), its labels, the on-demand request, the
--    batch and switch, and the two catalogued jobs resumed. It starts nothing until the paste file has widened the two CHECK constraints, and runs once.
create or replace function security.lean_entry_qualify_start_v1() returns jsonb
language plpgsql security definer set search_path = '' as $function$
begin
  if not exists (select 1 from pg_constraint where conname = 'lean_qualify_cases_field_check' and pg_get_constraintdef(oid) like '%entry_requirements%')
     or not exists (select 1 from pg_constraint where conname = 'lean_section_eval_cases_gold_source_check' and pg_get_constraintdef(oid) like '%ai_earlier%') then
    return jsonb_build_object('started', false, 'why', 'the two harness CHECK constraints are not widened yet (PASTE-20261125-s1125-lean-harness-entry-labels.sql)');
  end if;
  if exists (select 1 from pipeline.lean_qualify_cases where run_label = 's1125-entry-qualify-2026-11-25') then
    return jsonb_build_object('started', false, 'why', 'the run is already seeded');
  end if;
  -- the cohort (Admin #1063 conditions) and its labels
  create temp table s1125_coh on commit drop as
    select distinct on (o.course_id) o.course_id, o.provider_id, d.evidence_id
      from pipeline.aer_course_outcomes o join pipeline.aer_det_academic_pages d on d.course_id = o.course_id
     where o.identity_basis in ('cricos_code', 'adapter_code', 'manual') and o.page_status = 'bound' and o.outcome in ('no_requirement_published', 'admitted_provider')
       and o.read_state = 'skipped'
       and o.provider_id = any (array[
      '4f86e09a-557c-4544-a0a3-3eb5dc8468a9', '53eaf404-8f22-46ff-a208-b0e82da4284e', '2968fe36-b879-4b53-8318-664ed56d291a', '658d593d-cd4a-4940-9927-0d471776284e',
      'eb9e3903-6d92-4502-a2b3-51cb231b21fc', 'c537423d-028a-4b06-b135-003f2c6c393d', '4b0e9d62-2ad7-4467-911c-1571e30a74d6', '80e8f5fd-1b38-4292-90ab-adafc9884381',
      '21e1cb6d-9c85-431f-b354-43b7370e5f40', '104f3038-862c-445d-aaf3-b8727ff756f3', '5c234f7f-a84c-46ae-b2ef-bfa75b59badd', '8495927d-cbd8-426d-814c-fa87d1a966e7',
      '9aa61e05-ec5e-4468-8d2e-c3c6fb984f37', 'c33ab783-ac3e-43a6-b00d-ce9ac4356ec5', 'f0c0f1dc-e628-4bb7-9943-727f32b26d50', 'f2ec4927-522c-42a7-8de4-33ada6684595',
      '4b41907a-5f10-4aaf-863d-ec5f5cec37a8', '566d1775-00c8-49da-8029-8d8a1291fe48', '9aed1f1c-6281-494f-a141-d8ebd4572b85', 'e2b73078-8636-459c-8d19-9129122fb301',
      'f16868c3-5487-487f-92cd-88e63116765c', '1df6d6f3-f957-46c1-8611-9047a84b1e61', '28ffde14-bf9d-404e-bbe7-fd97bdf56bb1', '87e9331c-a879-483c-8df7-337a2be7731d',
      'f71e9851-e4eb-4855-9931-eb42a4daef8d', '4bd30aeb-ffe4-4c0d-9794-db5ff7513628', '92355fb2-bf7a-42ed-81a4-598b5953145a', 'fe18f1f7-a15a-4328-a5db-fd67af56ca6c',
      '496cda02-c474-41f7-9358-3cf435164dc7', '71362bf9-2a99-4eb1-a76f-b5382dab9130', '7304f7c0-3097-49a6-a1e2-37b46e4e75ce', '89addf70-055c-4895-8e54-df7b9ffae4d6',
      '93aaad55-812a-482c-ad1e-7df0ac0a5a76', '9b833af0-5ac9-4764-9266-318e81641f1c', '9e69f830-39aa-4d64-a55d-1ccb12d420b6', 'e3e541d8-c2f4-4923-a54a-024ee209276e',
      'b93a1c45-c912-4711-a381-df226f3db646', 'c188e2fc-deb4-45a4-a593-6c4560890bcb', '26eabe05-21e4-4257-9bd2-6c0cf161b23d', '2ca823cc-8641-4828-926a-e0627055582b'
       ]::uuid[])
     order by o.course_id, d.read_at desc nulls last;
  create temp table s1125_e53 on commit drop as
    select c.course_id, c.provider_id, i.evidence_id, e.storage_path,
           (select jsonb_agg(jsonb_build_object('quote', left(q.quote, 300), 'kind', q.kind, 'audience', q.audience, 'min_entry_score', q.min_entry_score,
                    'min_entry_score_basis', q.min_entry_score_basis, 'benchmark_band', q.benchmark_band, 'min_grade', q.min_grade, 'row_id', q.id) order by q.created_at, q.id)
              from catalogue.course_entry_requirements q where q.course_id = c.course_id and q.status = 'inactive') gold
      from s1125_coh c
      join lateral (select li.evidence_id from pipeline.layer4_review_items li where li.entity_id = c.course_id and li.field_code = 'course_entry_first_read' and li.status = 'superseded'
                     order by li.created_at desc limit 1) i on true
      join pipeline.evidence_artifacts e on e.id = i.evidence_id
     where e.storage_path ~ '\.html';
  create temp table s1125_acc on commit drop as
    select z.course_id, z.provider_id, z.evidence_id, e.storage_path,
           (select jsonb_agg(jsonb_build_object('quote', left(l.quote, 300), 'min_value', l.min_value, 'min_grade', l.min_grade, 'grade_scale', l.grade_scale, 'benchmark_band', l.benchmark_band, 'row_id', l.row_id) order by l.row_id)
              from pipeline.aer_labelled_rows_v1 l where l.source_kind = 'course_page' and l.label = 'accepted' and l.evidence_id = z.evidence_id and l.course_id = z.course_id) gold
      from (select distinct on (l.provider_id) l.provider_id, l.course_id, l.evidence_id
              from pipeline.aer_labelled_rows_v1 l
             where l.source_kind = 'course_page' and l.label = 'accepted' and l.course_id is not null and l.evidence_id is not null
               and exists (select 1 from catalogue.providers pr join ref.countries k on k.id = pr.country_id where pr.id = l.provider_id and k.iso_alpha2 = 'AU')
               and not exists (select 1 from s1125_coh c where c.course_id = l.course_id)
             order by l.provider_id, md5(l.evidence_id::text)) z
      join pipeline.evidence_artifacts e on e.id = z.evidence_id
     where e.storage_path ~ '\.html'
     order by md5(z.provider_id::text)
     limit 30;  -- fixed: the size of the independent-label sample (Admin #1063 qualification)

  declare v_eval constant text := 's1125-entry-cohort-2026-11-25'; v_q constant text := 's1125-entry-qualify-2026-11-25'; v_a int; v_b int; v_c int; v_d int;
    v_models constant text[] := array['deepseek-v4-flash', 'qwen3-30b', 'mistral-small-3.2', 'mimo-v2.6-flash'];
  begin
    if (select count(*) from pipeline.ai_model_catalogue where code = any (v_models) and status = 'allowed') <> 4 then raise exception 's1125: a candidate model is not allowed in the catalogue'; end if;
    -- offline recall (no AI): each earlier row as a label on the page that earlier read used; each cohort page for its sizes
    insert into pipeline.lean_section_eval_cases (run_label, field, gold_source, source_ref, course_id, evidence_id, storage_path, gold)
    select v_eval, 'entry_requirements', 'ai_earlier', g->>'row_id', x.course_id, x.evidence_id, x.storage_path, jsonb_build_array(left(g->>'quote', 160))  -- fixed: the compared opening of a long quote (the existing seed's rule)
      from s1125_e53 x cross join lateral jsonb_array_elements(coalesce(x.gold, '[]'::jsonb)) g
     where length(security.aer_flat_v1(g->>'quote')) >= 12
    on conflict do nothing;
    get diagnostics v_a = row_count;
    insert into pipeline.lean_section_eval_cases (run_label, field, gold_source, source_ref, course_id, evidence_id, storage_path, gold)
    select v_eval, 'entry_requirements', 'cohort_size', c.course_id::text, c.course_id, c.evidence_id, e.storage_path, '[]'::jsonb
      from s1125_coh c join pipeline.evidence_artifacts e on e.id = c.evidence_id where e.storage_path ~ '\.html'
    on conflict do nothing;
    get diagnostics v_b = row_count;
    -- qualification (paid, under the ceiling): page by page, the four models in turn
    insert into pipeline.lean_qualify_cases (run_label, field, kind, source_ref, course_id, evidence_id, storage_path, gold, model_code, gold_source)
    select v_q, 'entry_requirements', 'positive', p.course_id || ':' || m.code, p.course_id, p.evidence_id, p.storage_path, p.gold, m.code, p.src
      from (select x.course_id, x.evidence_id, x.storage_path, x.gold, 'ai_earlier' src from s1125_e53 x where jsonb_array_length(coalesce(x.gold, '[]'::jsonb)) > 0
            union all
            select a.course_id, a.evidence_id, a.storage_path, a.gold, 'aer_accepted' from s1125_acc a where jsonb_array_length(coalesce(a.gold, '[]'::jsonb)) > 0) p
      cross join unnest(v_models) with ordinality m(code, k)
     order by md5(p.course_id::text), m.k
    on conflict do nothing;
    get diagnostics v_c = row_count;
    select count(*) into v_d from s1125_coh;
    if v_c > 400 then raise exception 's1125: % qualification cases, more than planned (332)', v_c; end if;  -- fixed: the planned run's size
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('ai_eval', 'seed', 'pipeline.lean_qualify_cases', jsonb_build_object('reason', 'P0 AER preprocessing (Platform Admin 25 Nov 2026 08:16 AEDT, Admin #1063)', 'by', 'security.lean_entry_qualify_start_v1 (CF-247 s1125)',
            'eval_run', v_eval, 'eval_ai_earlier_labels', v_a, 'eval_cohort_pages', v_b, 'cohort_courses', v_d, 'earlier_answer_pages', (select count(*) from s1125_e53),
            'earlier_rows', (select coalesce(sum(jsonb_array_length(gold)), 0) from s1125_e53), 'accepted_pages', (select count(*) from s1125_acc), 'qualify_run', v_q, 'qualify_cases', v_c, 'models', to_jsonb(v_models)), null);
    raise notice 's1125: eval labels %, cohort pages %, qualify cases % (cohort %)', v_a, v_b, v_c, v_d;
  end;

  -- spend opened on demand, batch and switch through the settings pattern, the two catalogued jobs resumed
  declare v_reason constant text := 'P0 AER preprocessing (Platform Admin 25 Nov 2026 08:16 AEDT, Admin #1063): entry requirements qualification of the selected input on four allowed models; stored pages only, nothing admitted';
    v_od jsonb; s record; r record; v_prov uuid[];
  begin
    select array_agg(distinct x.provider_id) into v_prov from (select provider_id from s1125_e53 union select provider_id from s1125_acc) x;
    v_od := security.on_demand_open_v1('claude_session', v_reason, v_prov, jsonb_build_object('openrouter_usd', 0.60, 'calls', 700, 'firecrawl_credits', 0, 'ceiling_usd', security.pipeline_num_v1('reading.lean_qualify_ceiling_usd', 0)), null, array['openrouter']);
    for s in select * from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('batch.lean_qualify', 'reading.lean_qualify_on') for update loop
      if s.key = 'batch.lean_qualify' and (3 < coalesce(s.min_value, 3) or 3 > coalesce(s.max_value, 3)) then raise exception 's1125: 3 is outside batch.lean_qualify''s range'; end if;
      update pipeline.platform_toolset_settings set value = case when s.key = 'batch.lean_qualify' then to_jsonb(3) else to_jsonb(1) end, reason = v_reason, updated_at = now()
       where toolset_key = 'pipeline' and key = s.key;
      insert into pipeline.admin_control_events(area, action, target, detail, actor)
      values ('toolsets', 'setting', 'pipeline.' || s.key, jsonb_build_object('before', s.value, 'after', case when s.key = 'batch.lean_qualify' then to_jsonb(3) else to_jsonb(1) end, 'reason', v_reason,
              'approved_by', 'Platform Admin (chat, 25 Nov 2026 08:16 AEDT)', 'via', 'CF-247 s1125 migration', 'on_demand', v_od->'id'), null);
    end loop;
    for r in select j.jobid, j.jobname from cron.job j where j.jobname in ('lean-qualify', 'lean-sections-eval') and not j.active loop
      perform cron.alter_job(r.jobid, active => true);
      insert into pipeline.admin_control_events (area, action, target, detail, actor)
      values ('automations', 'resume', r.jobname, jsonb_build_object('reason', v_reason, 'by', 'security.lean_entry_qualify_start_v1 (CF-247 s1125)'), null);
    end loop;
  end;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active cron jobs'; end if;
  return jsonb_build_object('started', true,
    'eval_cases', (select count(*) from pipeline.lean_section_eval_cases where run_label = 's1125-entry-cohort-2026-11-25'),
    'qualify_cases', (select count(*) from pipeline.lean_qualify_cases where run_label = 's1125-entry-qualify-2026-11-25'),
    'on_demand', (select r.id from pipeline.on_demand_requests r where r.reason like 'P0 AER preprocessing%' order by r.expires_at desc limit 1),
    'cron_active', (select count(*) from cron.job where active));
end $function$;
comment on function security.lean_entry_qualify_start_v1() is 'CF-247 s1125 (P0 AER preprocessing, Admin #1063): seeds the entry recall check (152 earlier rows, 225 cohort pages) and the entry qualification run (53 earlier-answer pages and 30 Layer 4 accepted pages on four allowed models), opens the on-demand request, sets reading.lean_qualify_on 1 and batch.lean_qualify 3, and resumes jobs lean-qualify and lean-sections-eval. Called by the Platform Admin''s paste file after the two harness CHECK constraints are widened; refuses before that, and runs once.';
revoke all on function security.lean_entry_qualify_start_v1() from public, anon, authenticated;

-- started here only if the constraints are already widened (they are not when this migration is applied; the paste file calls it)
do $start$
begin
  raise notice 's1125: %', security.lean_entry_qualify_start_v1();
end $start$;


do $c$
declare v_api jsonb;
begin
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active cron jobs'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1125_locks) then raise exception 'post-check: manual locks changed'; end if;
  if security.pipeline_num_v1('reading.course_entry_sections_on', 0) <> 1 then raise exception 'post-check: sections-first is not on'; end if;
  if exists (select 1 from pipeline.ai_service_routes where service_code = 'course_entry_requirements' and enabled) then raise exception 'post-check: the course entry route was switched on'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
