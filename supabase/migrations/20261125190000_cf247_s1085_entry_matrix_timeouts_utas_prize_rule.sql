-- CF-247 s1085 (S1-Build; Platform Admin 24 Nov 2026 22:02 and 22:07 AEDT: AER-FU-11 option 3, SCH-FU-02 UTAS rule in migration history).
-- Found live (rolled back, 24 Nov 2026 20:05 to 22:20 AEDT):
--   * entry_matrices: 10 Canadian college runs, plus Deakin, ECU, Bond and Newcastle, failed after three tries with "reply unreadable: TimeoutError" or
--     "time budget". The worker called the model with no cascade list (cascadeFetch got only the service), so the route's next qualified models
--     (Qwen3 30B, GPT-4.1 mini) were never asked; each slice waited 90 s inside a 110 s run, and the run was repeated unchanged three times.
--     Slices are 8,000 characters (entry.matrix_slice_chars) with up to 16,000 output tokens.
--   * S1-Scholarship-Claude added pipeline.scholarship_skip_rules row 10 ("UTAS enrolled-student prize") live on 24 Nov 2026 21:41 AEDT; it is not in
--     migration history. 192 UTAS Prizes A-Z candidates are skipped by it, 5 remain unread.
-- What changes (live on deploy):
--   1. entry.matrix_slice_chars 8,000 -> 4,000 (its range is 4,000 to 24,000), logged with the Platform Admin's approval. Worker v1.0.39 sends each
--      slice through the route's qualified cascade with the run's deadline and a 40 s first-model time-out, so a timed-out slice goes to the next
--      model; failed attempts are noted in the AI call log (pipeline.ai_invocations) like every cascade call.
--   2. The UTAS rule is written into history as it stands live (inserted only if absent; nothing else changes).
--   3. The 13 failed runs named by the Platform Admin are queued again, leased for 15 minutes so the new worker (deployed with this change) reads them.
-- G1: no job. G2: the slice size is a setting, changed with a reason; the 40 s is an API time-out (fixed, in code). G3: checked. Locks and cron checked.
-- Replaces: a single-model entry_matrices call repeated three times on a time-out.
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '60s';  -- fixed: the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1085_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1085_cron on commit drop as select count(*) n from cron.job where active;

-- 1. slice size, as the settings writer does it (range, reason, event)
do $set$
declare v_before jsonb; s record; v_reason text := 'AER-FU-11 option 3 (Platform Admin 24 Nov 2026 22:02 and 22:07 AEDT): halve the entry_matrices slice so each model answer fits its time-out';
begin
  select * into s from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'entry.matrix_slice_chars' for update;
  if s.key is null then raise exception 's1085: setting entry.matrix_slice_chars not found'; end if;
  if (s.min_value is not null and 4000 < s.min_value) or (s.max_value is not null and 4000 > s.max_value) then raise exception 's1085: 4000 is outside the setting''s range'; end if;
  v_before := s.value;
  update pipeline.platform_toolset_settings set value = to_jsonb(4000), reason = v_reason, updated_at = now() where toolset_key = 'pipeline' and key = 'entry.matrix_slice_chars';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('toolsets', 'setting', 'pipeline.entry.matrix_slice_chars', jsonb_build_object('before', v_before, 'after', to_jsonb(4000), 'reason', v_reason,
          'approved_by', 'Platform Admin (chat, 24 Nov 2026 22:02 and 22:07 AEDT)', 'via', 'CF-247 s1085 migration'), null);
end $set$;

-- 2. S1-Scholarship-Claude's live UTAS rule, in history as it stands (SCH-FU-02)
insert into pipeline.scholarship_skip_rules(pattern, label, active, unless_pattern, reason, added_by, added_at, updated_at)
select '^https?://www\.utas\.edu\.au/study/scholarships-fees-and-costs/prizes/a-z\?code=PRZ_', 'UTAS enrolled-student prize', true, 'international',
       'S1-Scholarship-Claude SCH-FU-09 24 Nov 2026: UTAS Prizes A-Z entries are in-course academic achievement prizes for enrolled students; 8 of 8 stored copies read show no international wording, 0 of 201 candidates are international_explicit; genuine international UTAS scholarships live on other URLs (9 published) and are not matched; any URL containing international is exempt',
       null, '2026-11-24T10:41:24.783464+00:00', '2026-11-24T10:41:24.783464+00:00'
 where not exists (select 1 from pipeline.scholarship_skip_rules r where r.pattern = '^https?://www\.utas\.edu\.au/study/scholarships-fees-and-costs/prizes/a-z\?code=PRZ_');

-- 3. the named failed runs, queued again for the new worker
do $rq$
declare v_n int;
begin
  with t as (
    select r.id from pipeline.entry_matrix_runs r join catalogue.providers p on p.id = r.provider_id
     where r.state = 'failed' and r.error ~* 'timed out|time budget|without a reply'
       and (p.canonical_name ~* '^(Niagara College|Thompson Rivers|Georgian College|Confederation College|Capilano University|Humber College|La Cit|Algonquin College|George Brown College|Vancouver Island University|Deakin University|Edith Cowan University|Bond University)'))
  update pipeline.entry_matrix_runs r set state = 'queued', attempts = 0, leased_until = now() + interval '15 minutes', updated_at = now(),  -- fixed: wait for the worker deploy
         error = 'requeued by CF-247 s1085 (AER-FU-11): ' || left(coalesce(r.error, ''), 300)
    from t where r.id = t.id;
  get diagnostics v_n = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('aer', 'requeue', 'entry_matrix_runs', jsonb_build_object('runs', v_n, 'reason', 'AER-FU-11: timed-out runs, read again through the cascade',
          'approved_by', 'Platform Admin (chat, 24 Nov 2026 22:02 and 22:07 AEDT)', 'via', 'CF-247 s1085 migration'), null);
  raise notice 's1085: % run(s) queued again', v_n;
end $rq$;

do $c$
declare v_api jsonb;
begin
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'entry.matrix_slice_chars') <> to_jsonb(4000) then raise exception 'post-check: the slice size is not 4000'; end if;
  if (select count(*) from pipeline.scholarship_skip_rules where label = 'UTAS enrolled-student prize' and active) <> 1 then raise exception 'post-check: the UTAS rule is not there once'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1085_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1085_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
