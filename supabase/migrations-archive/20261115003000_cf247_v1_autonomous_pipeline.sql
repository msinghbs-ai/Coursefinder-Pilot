-- CF-247 worker v1.0.0, autonomous pipeline release (Platform Admin 15 Nov 2026 00:23). Numbered after #1148/#1149 (20261114201500).
-- Three parts, each one ships observing or switched off; the Platform Admin switches them on after v1.0.0 deploys green:
--   1. Markdown input: worker readers take Firecrawl's markdown of a stored page when reading.markdown_input is 1 (ships 0). Worker only; the
--      setting is added here.
--   2. Self-improving cascade: job ai-model-health (every 10 minutes) keeps each service's models' rolling success, empty-answer, time-out and
--      failure rates, median time and cost (pipeline.ai_model_health, from pipeline.ai_invocations and the new pipeline.ai_attempt_times). A model whose
--      failure rate over health.ai_window_minutes reaches health.ai_fail_rate_pct on at least health.ai_min_attempts attempts is put in cooldown for
--      health.ai_cooldown_minutes (extended while it keeps failing, ended by itself when it stops), and raises a notice. The worker asks a cooling
--      model after the healthy ones of the same cascade only when health.ai_reorder_on is 1 (ships 0). Nothing is added to a cascade or removed from
--      one; allowed and qualified models only, as handed out by security.ai_route_v1.
--   3. Self-healing Layer 4: job layer4-drain (every 30 minutes) looks at pending Layer 4 items older than layer4.drain_min_age_days and records a
--      verdict for each (pipeline.layer4_drain_state): a newer item for the same field (superseded), a course page that is gone or no longer the
--      course (returned to Layer 2), a page not read again since the item came (read again), read again and still waiting (needs a person). With
--      layer4.drain_on 0 (as shipped) nothing changes: the verdicts are recorded only. With it on, the action is taken; a read again is asked at most
--      layer4.drain_max_attempts times with an exponential cooldown (layer4.drain_cooldown_hours, doubled each time), then the item is a dead letter
--      (kept pending, counted in a notice, never asked again by this job). Items whose status change has its own trigger (course description, course
--      entry, entry matrix, no page, conjoint rule and provider description reviews) and AER items are never changed by this job.
-- Lock rule (#1149): no ALTER of any existing table. New tables, new functions, rows in pipeline.platform_toolset_settings (an INSERT, never an
-- ALTER), md5-guarded edits of two functions.
-- Unchanged: every route switch, aer.v2_shadow_on, the OpenRouter Observe/Stop mode, every budget ceiling and cap, every paused queue.
-- G1: two new jobs, both catalogued. G2: every window, rate, age, attempt count, cooldown and batch is a setting (toolset pipeline).
-- G3: no consumer API object is read or changed.
-- Replaces: public.svc_ai_model_answered_v1(text,text,text,jsonb,text) and security.platform_notices_v1() (same names and signatures; md5-guarded edits
--   of the live text).
-- Retires: nothing.

set local lock_timeout = '3s';

-- 1. New tables
create table if not exists pipeline.ai_attempt_times (
  id bigserial primary key,
  at timestamptz not null default now(),
  service_code text,
  model text not null,
  outcome text not null,
  ms integer not null
);
create index if not exists ai_attempt_times_at_idx on pipeline.ai_attempt_times (at);
comment on table pipeline.ai_attempt_times is 'CF-247 worker v1.0.0: how long each AI call attempt took (ms), as the worker noted it in cascade.ts, beside pipeline.ai_invocations (which has no time). Read by security.ai_model_health_refresh_v1 for the median time per service and model.';
alter table pipeline.ai_attempt_times enable row level security;

create table if not exists pipeline.ai_model_health (
  service_code text not null,
  model text not null,
  window_minutes integer not null,
  attempts integer not null default 0,
  answered integer not null default 0,
  failed integer not null default 0,
  empty integer not null default 0,
  timeouts integer not null default 0,
  fail_rate numeric,
  empty_rate numeric,
  median_ms integer,
  cost_usd numeric not null default 0,
  cost_per_answer numeric,
  state text not null default 'ok' check (state in ('ok', 'cooling')),
  cooling_since timestamptz,
  cooling_until timestamptz,
  checked_at timestamptz not null default now(),
  primary key (service_code, model)
);
comment on table pipeline.ai_model_health is 'CF-247 worker v1.0.0 self-improving cascade: rolling health of each model of each AI service over health.ai_window_minutes (attempts, answers, failures, empty answers, time-outs, median time, cost), kept by job ai-model-health. state cooling: the failure rate reached health.ai_fail_rate_pct; the worker asks the model after the healthy ones of the cascade until cooling_until, only when health.ai_reorder_on is 1.';
alter table pipeline.ai_model_health enable row level security;

create table if not exists pipeline.layer4_drain_state (
  item_id uuid primary key,
  verdict text not null,
  action text not null,
  applied boolean not null default false,
  attempts integer not null default 0,
  first_at timestamptz not null default now(),
  last_at timestamptz not null default now(),
  next_at timestamptz not null default now(),
  dead_letter_at timestamptz,
  detail jsonb
);
create index if not exists layer4_drain_state_next_idx on pipeline.layer4_drain_state (next_at);
comment on table pipeline.layer4_drain_state is 'CF-247 worker v1.0.0 self-healing Layer 4: one row per pending Layer 4 item job layer4-drain has looked at: its verdict (superseded_by_newer, page_gone, read_again, needs_person, left_for_person, dead_letter), the action (taken only when layer4.drain_on is 1; applied says whether it was), how often a read again was asked, when it is looked at next (exponential cooldown) and when it became a dead letter.';
alter table pipeline.layer4_drain_state enable row level security;

-- 2. Settings (INSERT only; the table is never altered)
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values
 ('pipeline', 'reading.markdown_input', 'Readers take Firecrawl''s markdown of a stored page',
  '1: the course fields, scholarship AI and AER v2 trial readers take the markdown Firecrawl returned with a stored page (kept beside it since worker v0.99.0), when it exists; 0: they convert the stored HTML, as before. Quotes are checked on the text the model was given.',
  'number', '0'::jsonb, 0, 1, 'on (1) or off (0)', 1460, 'Worker v1.0.0, Platform Admin 15 Nov 2026 00:23 (ships off)', 'Enrich fields', 'worker coverage-sweep v1.0.0: enrich_ai, scholarship_ai, aer_v2_shadow'),
 ('pipeline', 'health.ai_window_minutes', 'AI model health: window', 'How far back job ai-model-health counts each model''s attempts for a service.',
  'number', '60'::jsonb, 10, 1440, 'minutes', 1470, 'Worker v1.0.0 (ships observing)', 'Self-healing', 'job ai-model-health; security.ai_model_health_refresh_v1'),
 ('pipeline', 'health.ai_min_attempts', 'AI model health: attempts before judging', 'A model is judged only when it had at least this many attempts for the service in the window.',
  'number', '10'::jsonb, 3, 500, 'attempts', 1471, 'Worker v1.0.0 (ships observing)', 'Self-healing', 'job ai-model-health; security.ai_model_health_refresh_v1'),
 ('pipeline', 'health.ai_fail_rate_pct', 'AI model health: failure rate that starts a cooldown', 'Failed attempts (errors, time-outs, empty, cut or non-JSON answers) as a share of all attempts in the window.',
  'number', '50'::jsonb, 5, 100, '%', 1472, 'Worker v1.0.0 (ships observing)', 'Self-healing', 'job ai-model-health; security.ai_model_health_refresh_v1'),
 ('pipeline', 'health.ai_cooldown_minutes', 'AI model health: cooldown', 'How long a failing model stays in cooldown after its last failing check; it recovers by itself after that.',
  'number', '30'::jsonb, 5, 1440, 'minutes', 1473, 'Worker v1.0.0 (ships observing)', 'Self-healing', 'job ai-model-health; security.ai_model_health_refresh_v1'),
 ('pipeline', 'health.ai_reorder_on', 'AI model health: ask cooling models last', '1: the worker asks a model in cooldown after the healthy models of the same cascade (only the order changes); 0: cascades keep their own order and cooldowns are reported only.',
  'number', '0'::jsonb, 0, 1, 'on (1) or off (0)', 1474, 'Worker v1.0.0, Platform Admin 15 Nov 2026 00:23 (ships off)', 'Self-healing', 'worker coverage-sweep v1.0.0 cascade.ts; public.svc_ai_model_health_v1'),
 ('pipeline', 'layer4.drain_on', 'Layer 4 self-healing: take the action', '1: job layer4-drain acts on its verdicts (superseded, returned to Layer 2, read again); 0: it records the verdicts only.',
  'number', '0'::jsonb, 0, 1, 'on (1) or off (0)', 1480, 'Worker v1.0.0, Platform Admin 15 Nov 2026 00:23 (ships off)', 'Self-healing', 'job layer4-drain; security.layer4_drain_tick_v1'),
 ('pipeline', 'layer4.drain_min_age_days', 'Layer 4 self-healing: pending at least', 'Only items pending at least this long are looked at.',
  'number', '7'::jsonb, 1, 90, 'days', 1481, 'Worker v1.0.0', 'Self-healing', 'job layer4-drain; security.layer4_drain_tick_v1'),
 ('pipeline', 'layer4.drain_max_attempts', 'Layer 4 self-healing: reads again before a dead letter', 'How many times a course page is read again for one item before the item is a dead letter.',
  'number', '3'::jsonb, 1, 10, 'reads', 1482, 'Worker v1.0.0', 'Self-healing', 'job layer4-drain; security.layer4_drain_tick_v1'),
 ('pipeline', 'layer4.drain_cooldown_hours', 'Layer 4 self-healing: first wait before looking again', 'Doubled after each read again (24, 48, 96 hours ...).',
  'number', '24'::jsonb, 1, 720, 'hours', 1483, 'Worker v1.0.0', 'Self-healing', 'job layer4-drain; security.layer4_drain_tick_v1'),
 ('pipeline', 'batch.layer4_drain', 'Layer 4 self-healing: items a run', 'Pending items job layer4-drain looks at in one run.',
  'number', '200'::jsonb, 10, 2000, 'items', 1484, 'Worker v1.0.0', 'Job sizes', 'job layer4-drain')
on conflict (toolset_key, key) do nothing;

-- 3. Model health: refresh, the worker's read, and the report
create or replace function security.ai_model_health_refresh_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_win int := security.pipeline_num_v1('health.ai_window_minutes', 60)::int;
        v_min int := security.pipeline_num_v1('health.ai_min_attempts', 10)::int;
        v_rate numeric := security.pipeline_num_v1('health.ai_fail_rate_pct', 50) / 100.0;
        v_cool int := security.pipeline_num_v1('health.ai_cooldown_minutes', 30)::int;
        v_run timestamptz := now(); v_n int; v_cooling int;
begin
  insert into pipeline.ai_model_health as h (service_code, model, window_minutes, attempts, answered, failed, empty, timeouts, fail_rate, empty_rate,
                                             median_ms, cost_usd, cost_per_answer, state, cooling_since, cooling_until, checked_at)
  select s.service_code, s.model, v_win, s.attempts, s.answered, s.failed, s.empty, s.timeouts,
         round(s.failed::numeric / s.attempts, 4), round(s.empty::numeric / s.attempts, 4), t.median_ms, s.cost,
         case when s.answered > 0 then round(s.cost / s.answered, 6) end,
         case when s.attempts >= v_min and s.failed::numeric / s.attempts >= v_rate then 'cooling' else 'ok' end,
         case when s.attempts >= v_min and s.failed::numeric / s.attempts >= v_rate then v_run end,
         case when s.attempts >= v_min and s.failed::numeric / s.attempts >= v_rate then v_run + make_interval(mins => v_cool) end,
         v_run
    from (select i.service_code, i.model, count(*)::int attempts, count(*) filter (where i.outcome = 'answered')::int answered,
                 count(*) filter (where i.outcome = 'failed')::int failed, count(*) filter (where i.failure_kind = 'empty')::int empty,
                 count(*) filter (where i.failure_kind = 'timeout')::int timeouts, coalesce(sum(i.cost_usd), 0) cost
            from pipeline.ai_invocations i
           where i.at > v_run - make_interval(mins => v_win) and i.service_code is not null and i.model is not null
           group by 1, 2) s
    left join (select a.service_code, a.model, (percentile_cont(0.5) within group (order by a.ms))::int median_ms
                 from pipeline.ai_attempt_times a where a.at > v_run - make_interval(mins => v_win) and a.service_code is not null group by 1, 2) t
      on t.service_code = s.service_code and t.model = s.model
  on conflict (service_code, model) do update set
    window_minutes = excluded.window_minutes, attempts = excluded.attempts, answered = excluded.answered, failed = excluded.failed,
    empty = excluded.empty, timeouts = excluded.timeouts, fail_rate = excluded.fail_rate, empty_rate = excluded.empty_rate,
    median_ms = excluded.median_ms, cost_usd = excluded.cost_usd, cost_per_answer = excluded.cost_per_answer, checked_at = excluded.checked_at,
    -- still failing: the cooldown is extended; no longer failing: it ends by itself when cooling_until passes
    state = case when excluded.state = 'cooling' then 'cooling' when h.cooling_until > v_run then 'cooling' else 'ok' end,
    cooling_since = case when excluded.state = 'cooling' then coalesce(case when h.state = 'cooling' then h.cooling_since end, v_run)
                         when h.cooling_until > v_run then h.cooling_since end,
    cooling_until = case when excluded.state = 'cooling' then excluded.cooling_until when h.cooling_until > v_run then h.cooling_until end;
  get diagnostics v_n = row_count;
  -- models with no attempt in the window: nothing to judge; a running cooldown ends at its time
  update pipeline.ai_model_health h set attempts = 0, answered = 0, failed = 0, empty = 0, timeouts = 0, fail_rate = null, empty_rate = null,
         median_ms = null, cost_usd = 0, cost_per_answer = null, window_minutes = v_win, checked_at = v_run,
         state = case when h.cooling_until > v_run then 'cooling' else 'ok' end,
         cooling_since = case when h.cooling_until > v_run then h.cooling_since end,
         cooling_until = case when h.cooling_until > v_run then h.cooling_until end
   where h.checked_at < v_run;
  select count(*) into v_cooling from pipeline.ai_model_health where state = 'cooling';
  return jsonb_build_object('checked', v_n, 'cooling', v_cooling, 'at', v_run);
end $function$;
comment on function security.ai_model_health_refresh_v1() is 'CF-247 worker v1.0.0: job ai-model-health. Refreshes pipeline.ai_model_health from the attempts of the last health.ai_window_minutes; starts, extends and ends cooldowns (health.ai_min_attempts, health.ai_fail_rate_pct, health.ai_cooldown_minutes).';
revoke all on function security.ai_model_health_refresh_v1() from public, anon, authenticated;

create or replace function public.svc_ai_model_health_v1() returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v_on boolean := security.pipeline_num_v1('health.ai_reorder_on', 0) = 1;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return jsonb_build_object('reorder_on', v_on,
    'cooling', case when v_on then coalesce((select jsonb_object_agg(z.service_code, z.models) from (
                 select h.service_code, jsonb_agg(h.model order by h.model) models from pipeline.ai_model_health h
                  where h.state = 'cooling' and h.cooling_until > now() group by 1) z), '{}'::jsonb) else '{}'::jsonb end);
end $function$;
comment on function public.svc_ai_model_health_v1() is 'CF-247 worker v1.0.0: the models each AI service has in cooldown, for the worker (cascade.ts asks them after the healthy ones); empty unless health.ai_reorder_on is 1.';
revoke all on function public.svc_ai_model_health_v1() from public, anon, authenticated;
grant execute on function public.svc_ai_model_health_v1() to service_role;

create or replace function public.admin_ai_model_health_v1() returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  return jsonb_build_object('reorder_on', security.pipeline_num_v1('health.ai_reorder_on', 0) = 1,
    'models', coalesce((select jsonb_agg(to_jsonb(h) order by h.state desc, h.fail_rate desc nulls last, h.service_code, h.model) from pipeline.ai_model_health h), '[]'::jsonb));
end $function$;
comment on function public.admin_ai_model_health_v1() is 'CF-247 worker v1.0.0: the rolling health of every model of every AI service (pipeline.ai_model_health), for Curator and above.';
revoke all on function public.admin_ai_model_health_v1() from public, anon;
grant execute on function public.admin_ai_model_health_v1() to authenticated;

-- 4. Layer 4 self-healing
create or replace function security.layer4_drain_tick_v1(p_limit int) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_on boolean := security.pipeline_num_v1('layer4.drain_on', 0) = 1;
        v_age int := security.pipeline_num_v1('layer4.drain_min_age_days', 7)::int;
        v_max int := security.pipeline_num_v1('layer4.drain_max_attempts', 3)::int;
        v_hours int := security.pipeline_num_v1('layer4.drain_cooldown_hours', 24)::int;
        v_own_trigger text[] := array['course_description_first_read', 'course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change',
                                      'no_page_first_run', 'conjoint_rule_first_run', 'provider_description'];  -- fixed: the fields whose status change runs its own trigger
        r record; v_verdict text; v_action text; v_applied boolean; v_attempts int; v_next timestamptz; v_dead timestamptz; v_detail jsonb;
        v_out jsonb := '{}'::jsonb; v_page record;
begin
  for r in
    select i.*, d.attempts d_attempts, d.dead_letter_at d_dead
      from pipeline.layer4_review_items i
      left join pipeline.layer4_drain_state d on d.item_id = i.id
     where i.status = 'pending' and i.created_at < now() - make_interval(days => v_age)
       and (d.item_id is null or (d.next_at <= now() and d.dead_letter_at is null))
     order by i.created_at
     limit greatest(1, coalesce(p_limit, 1))
  loop
    v_applied := false; v_attempts := coalesce(r.d_attempts, 0); v_dead := null; v_detail := null;
    v_next := now() + make_interval(hours => v_hours);
    select c.read_status, c.http_status, c.read_at, c.leased_until into v_page from pipeline.coverage_course_pages c
     where r.entity_type = 'course' and c.course_id = r.entity_id;
    if exists (select 1 from pipeline.layer4_review_items j where j.entity_type = r.entity_type and j.entity_id = r.entity_id
                and j.field_code is not distinct from r.field_code and j.created_at > r.created_at and j.status in ('pending', 'approved', 'edited_approved')) then
      v_verdict := 'superseded_by_newer'; v_action := 'mark superseded';
    elsif r.entity_type = 'course' and v_page.read_status is not null
          and (v_page.http_status >= 400 or v_page.read_status in ('page_refused', 'not_course_page', 'identity_mismatch', 'identity_refused')) then
      v_verdict := 'page_gone'; v_action := 'return to Layer 2';
      v_detail := jsonb_build_object('read_status', v_page.read_status, 'http_status', v_page.http_status);
    elsif r.entity_type = 'course' and v_page.read_status is not null and (v_page.read_at is null or v_page.read_at < r.created_at) then
      if v_attempts >= v_max then v_verdict := 'dead_letter'; v_action := 'none: reads again used up'; v_dead := now();
      else v_verdict := 'read_again'; v_action := 'read the course page again'; end if;
    else
      v_verdict := 'needs_person'; v_action := 'none: the page was read again and the item still waits for a person';
    end if;
    if r.field_code = any (v_own_trigger) or r.field_code ilike 'entry%' or r.field_code ilike 'aer%' then
      if v_verdict <> 'needs_person' then v_detail := coalesce(v_detail, '{}'::jsonb) || jsonb_build_object('would', v_verdict); end if;
      v_verdict := 'left_for_person'; v_action := 'none: this review has its own trigger'; v_dead := null;
    end if;
    if v_on then
      begin
        if v_verdict = 'superseded_by_newer' then
          update pipeline.layer4_review_items set status = 'superseded', decided_at = now() where id = r.id and status = 'pending';
          v_applied := found;
        elsif v_verdict = 'page_gone' then
          update pipeline.layer4_review_items set status = 'returned_layer2', decided_at = now() where id = r.id and status = 'pending';
          v_applied := found;
        elsif v_verdict = 'read_again' then
          update pipeline.coverage_course_pages set next_read_at = now()
           where course_id = r.entity_id and (leased_until is null or leased_until < now());
          v_applied := found;
          if v_applied then v_attempts := v_attempts + 1; v_next := now() + make_interval(hours => v_hours * power(2, v_attempts - 1)::int); end if;
        end if;
      exception when others then
        v_applied := false; v_detail := coalesce(v_detail, '{}'::jsonb) || jsonb_build_object('error', left(sqlerrm, 200));
      end;
    end if;
    insert into pipeline.layer4_drain_state as s (item_id, verdict, action, applied, attempts, first_at, last_at, next_at, dead_letter_at, detail)
    values (r.id, v_verdict, v_action, v_applied, v_attempts, now(), now(), v_next, v_dead, v_detail)
    on conflict (item_id) do update set verdict = excluded.verdict, action = excluded.action, applied = excluded.applied, attempts = excluded.attempts,
      last_at = excluded.last_at, next_at = excluded.next_at, dead_letter_at = coalesce(s.dead_letter_at, excluded.dead_letter_at), detail = excluded.detail;
    v_out := jsonb_set(v_out, array[v_verdict], to_jsonb(coalesce((v_out->>v_verdict)::int, 0) + 1));
  end loop;
  return jsonb_build_object('acting', v_on, 'verdicts', v_out);
end $function$;
comment on function security.layer4_drain_tick_v1(int) is 'CF-247 worker v1.0.0: job layer4-drain. Looks at up to p_limit pending Layer 4 items older than layer4.drain_min_age_days and records a verdict in pipeline.layer4_drain_state; acts on it (superseded, returned to Layer 2, read again with an exponential cooldown, then a dead letter) only when layer4.drain_on is 1. Never changes an item whose review has its own trigger.';
revoke all on function security.layer4_drain_tick_v1(int) from public, anon, authenticated;

create or replace function public.admin_layer4_drain_v1() returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  return jsonb_build_object('acting', security.pipeline_num_v1('layer4.drain_on', 0) = 1,
    'verdicts', coalesce((select jsonb_object_agg(z.verdict, z.n) from (select s.verdict, count(*) n from pipeline.layer4_drain_state s
                           join pipeline.layer4_review_items i on i.id = s.item_id and i.status = 'pending' group by 1) z), '{}'::jsonb),
    'applied', (select count(*) from pipeline.layer4_drain_state where applied),
    'dead_letters', (select count(*) from pipeline.layer4_drain_state s join pipeline.layer4_review_items i on i.id = s.item_id and i.status = 'pending' where s.dead_letter_at is not null));
end $function$;
comment on function public.admin_layer4_drain_v1() is 'CF-247 worker v1.0.0: what job layer4-drain found for the pending Layer 4 items (by verdict), how many actions it took and how many dead letters wait, for Curator and above.';
revoke all on function public.admin_layer4_drain_v1() from public, anon;
grant execute on function public.admin_layer4_drain_v1() to authenticated;

-- 5. md5-guarded edits: attempt times are kept; degraded models and Layer 4 dead letters are notices
create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_old text, p_new text) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
end $f$;

select pg_temp.edit_once('public.svc_ai_model_answered_v1(text,text,text,jsonb,text)', '766f9f62d31ba2bdd34b8f2ea9a78c81',
  $o$      from jsonb_array_elements(p_attempts) x where nullif(x->>'model', '') is not null;
    get diagnostics n = row_count;$o$,
  $n$      from jsonb_array_elements(p_attempts) x where nullif(x->>'model', '') is not null;
    get diagnostics n = row_count;
    -- CF-247 worker v1.0.0: the time of each attempt, for the model health check (pipeline.ai_attempt_times)
    insert into pipeline.ai_attempt_times (service_code, model, outcome, ms)
    select nullif(x->>'service', ''), x->>'model', case when x->>'outcome' = 'answered' then 'answered' else 'failed' end, (x->>'ms')::int
      from jsonb_array_elements(p_attempts) x where nullif(x->>'model', '') is not null and coalesce(x->>'ms', '') ~ '^[0-9]{1,9}$';$n$);

select pg_temp.edit_once('security.platform_notices_v1()', '88cffd39d76483d6b91f8f4b092f47d7',
  $o$
  return v;
end $function$$o$,
  $n$
  -- CF-247 worker v1.0.0: AI models in cooldown for a service (job ai-model-health)
  v := v || coalesce((select jsonb_agg(jsonb_build_object('key', 'openrouter:2:model_degraded:' || h.service_code || ':' || h.model, 'layer', 2, 'toolset', 'openrouter',
      'kind', 'model_degraded', 'severity', 'warning',
      'title', format('AI model failing for %s: %s', h.service_code, h.model),
      'detail', format('%s of %s attempts failed in the last %s minutes (%s empty, %s timed out); in cooldown until %s.', h.failed, h.attempts, h.window_minutes,
                       h.empty, h.timeouts, to_char(h.cooling_until at time zone 'Australia/Melbourne', 'DD Mon HH24:MI')),
      'hint', case when security.pipeline_num_v1('health.ai_reorder_on', 0) = 1 then 'Nothing to do: the model is asked after the healthy ones of the cascade until its cooldown ends.'
                   else 'Reported only (health.ai_reorder_on is 0). Check the service''s cascade on Models & services › AI.' end,
      'count', h.failed, 'first_at', h.cooling_since, 'last_at', h.checked_at))
    from pipeline.ai_model_health h where h.state = 'cooling' and h.cooling_until > now()), '[]'::jsonb);
  -- CF-247 worker v1.0.0: Layer 4 items the self-healing job could not move (dead letters)
  v := v || coalesce((select jsonb_agg(jsonb_build_object('key', 'pipeline:4:layer4_dead_letter', 'layer', 4, 'toolset', 'pipeline', 'kind', 'layer4_dead_letter', 'severity', 'warning',
      'title', format('%s Layer 4 %s', z.n, case when z.n = 1 then 'item is a dead letter' else 'items are dead letters' end),
      'detail', 'Their course page was read again as many times as layer4.drain_max_attempts allows and they still wait.',
      'hint', 'Decide them by hand in Layer 4, or fix the course page binding.', 'count', z.n, 'first_at', z.f, 'last_at', z.l))
    from (select count(*) n, min(s.dead_letter_at) f, max(s.dead_letter_at) l from pipeline.layer4_drain_state s
            join pipeline.layer4_review_items i on i.id = s.item_id and i.status = 'pending' where s.dead_letter_at is not null) z where z.n > 0), '[]'::jsonb);

  return v;
end $function$$n$);

-- 6. Jobs: catalogued first, then scheduled (commands carry no number)
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('ai-model-health', 'Platform upkeep', 90, 'AI model health',
  'Every 10 minutes: counts each AI service''s model attempts over health.ai_window_minutes (answers, failures, empty answers, time-outs, median time, cost) into pipeline.ai_model_health; a model failing at health.ai_fail_rate_pct or more is put in cooldown and raises a notice. The worker asks it last only when health.ai_reorder_on is 1.',
  6, false, null),
 ('layer4-drain', 'Admission', 91, 'Layer 4 self-healing',
  'Every 30 minutes: looks at batch.layer4_drain pending Layer 4 items older than layer4.drain_min_age_days and records a verdict (superseded, page gone, read again, needs a person, dead letter). Acts on it only when layer4.drain_on is 1; never changes reviews that have their own trigger.',
  6, true, null)
on conflict do nothing;

do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'ai-model-health') then
    perform cron.schedule('ai-model-health', '*/10 * * * *', 'select security.ai_model_health_refresh_v1()');
  end if;
  if not exists (select 1 from cron.job where jobname = 'layer4-drain') then
    perform cron.schedule('layer4-drain', '7,37 * * * *', 'select security.layer4_drain_tick_v1(security.pipeline_num_v1(''batch.layer4_drain'', 200)::int)');
  end if;
end $j$;


insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.ai_attempt_times', 'Layer 2', 'AI', 'Time of each AI call attempt, for the model health check', 'active', '{}', '20261115003000'),
 ('table', 'pipeline.ai_model_health', 'Layer 2', 'AI', 'Rolling health of each model of each AI service; cooldowns', 'active', '{}', '20261115003000'),
 ('table', 'pipeline.layer4_drain_state', 'Layer 4', 'Layer 4', 'Self-healing verdicts, actions, reads again and dead letters of pending Layer 4 items', 'active', '{}', '20261115003000'),
 ('job', 'ai-model-health', 'Layer 2', 'AI', 'Refreshes AI model health every 10 minutes', 'active', '{}', '20261115003000'),
 ('job', 'layer4-drain', 'Layer 4', 'Layer 4', 'Layer 4 self-healing every 30 minutes (records only while layer4.drain_on is 0)', 'active', '{}', '20261115003000'),
 ('function', 'security.ai_model_health_refresh_v1', 'Layer 2', 'AI', 'Job ai-model-health', 'active', '{}', '20261115003000'),
 ('function', 'public.svc_ai_model_health_v1', 'Layer 2', 'AI', 'Cooling models for the worker', 'active', '{}', '20261115003000'),
 ('function', 'public.admin_ai_model_health_v1', 'Layer 2', 'AI', 'AI model health report', 'active', '{}', '20261115003000'),
 ('function', 'security.layer4_drain_tick_v1', 'Layer 4', 'Layer 4', 'Job layer4-drain', 'active', '{}', '20261115003000'),
 ('function', 'public.admin_layer4_drain_v1', 'Layer 4', 'Layer 4', 'Layer 4 self-healing report', 'active', '{}', '20261115003000')
on conflict do nothing;

-- 7. Post-checks: everything that acts ships off; nothing else moved
do $c$
begin
  if security.pipeline_num_v1('reading.markdown_input', 0) <> 0 or security.pipeline_num_v1('health.ai_reorder_on', 0) <> 0
     or security.pipeline_num_v1('layer4.drain_on', 0) <> 0 then
    raise exception 'post-check: markdown input, cascade reordering and Layer 4 actions ship off';
  end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'ai-model-health')
     or not exists (select 1 from pipeline.automation_catalogue where jobname = 'layer4-drain') then
    raise exception 'post-check: both jobs are catalogued';
  end if;
  if (public.svc_ai_model_health_v1()->'cooling') <> '{}'::jsonb then raise exception 'post-check: no cascade is reordered while health.ai_reorder_on is 0'; end if;
end $c$;
