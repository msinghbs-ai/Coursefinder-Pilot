-- CF-247 (15 Oct 2026): waste rules for data enrichment. Platform Admin, 15 Oct 2026 09:18: "If we are wasting resources on multiple tries
-- then tighten rules around it, recording, flagging and moving on, rather getting stuck an wasting resources." Decisions (multiple choice):
-- "Auto-pause idle jobs", "Yield-based retry cap", "No repeat reads unchanged", "Run admit jobs on new input"; approach "Top 50 by adapter,
-- flag the tail", then "Central pages, per course group" (separate change).
-- Measured before (7 days to 15 Oct): course-link-reverse ran every minute for about 16 s (6.5 hours of database time a day) and last read a page
-- on 30 Sep (2 courses bound ever); coverage-admit, coverage-admit-intakes and adapter-overwrite ran about 45 s every 10 minutes with coverage
-- flat; exit-awards-apply (hourly at :37) and adapter-overwrite (:40) rewrote the same 106 courses' delivery about 33 times each in 4 days;
-- AI course-page matching attempt 2 found a page 17% of the time and attempt 3 9%; firecrawl-targets and firecrawl-panel-figures deadlocked
-- 95 times a day; scholarship pages already stored were read again for a second model step.
-- 1 Settings (Pipeline settings › Waste rules)   2 Records: flags, input marks, idle watch, focus providers   3 Rules (functions)
-- 4 Replaced functions (md5-guarded)   5 Jobs: admit jobs run on new input; waste-guard; enrich-focus-refresh   6 First run
-- Nothing dropped or deleted: a job that produces nothing is paused (cron active false) and resumes by itself; a value is frozen through the
-- existing adapter exclusions; every stop is recorded in pipeline.enrichment_flags.

do $guard$
declare v_expected jsonb := '{"security.coverage_admission_apply_v1(integer,text,text[])": "c5ce945a22f4be39dff5a41f6e5ef4c5", "security.coverage_ai_match_prepare_v1(integer,integer)": "744dda6ce3c49d2481975d4e56afd262", "public.svc_course_link_search_next(integer)": "2c4d40559740576a20b33d6f404a842a", "public.svc_coverage_discovery_next(integer)": "7d6ae2fafb981e5b702e8609f18f2460", "security.exit_awards_apply_v2(uuid)": "53c4064a30bdfe50dcfc58abd92d4675", "security.firecrawl_panel_refresh_v1()": "89ce4d05d75316542572f5c1bcb53911", "public.svc_scholarship_ai_next(integer)": "3f1c5858629531c66f2537961cebb129", "security.platform_notices_v1()": "eb99486952e5e68ffa42e625f2376c92"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 1 Settings
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'waste.idle_pause_hours', 'Pause a watched job that has produced nothing for', 'A watched job with no output and nothing waiting for this long is paused and flagged. It resumes by itself when work arrives.', 'number', to_jsonb(24), 1, 168, 'hours', 700, 'Platform Admin 15 Oct 2026: "Auto-pause idle jobs"', 'Waste rules', 'waste-guard job'),
 ('pipeline', 'waste.admit_full_check_hours', 'Admit jobs: full check at least every', 'The admit jobs run when new pages, adapter changes, checked values, locks or decisions have arrived. Without new input they still do a full check this often.', 'number', to_jsonb(6), 1, 48, 'hours', 701, 'Platform Admin 15 Oct 2026: "Run admit jobs on new input"', 'Waste rules', 'coverage-admit, coverage-admit-intakes, adapter-overwrite'),
 ('pipeline', 'waste.retry_min_yield_pct', 'Try again only when a further try finds something in at least', 'A further attempt is made only while that attempt number has succeeded in at least this share of recent cases. After the last useful attempt the item is flagged and left.', 'number', to_jsonb(15), 0, 100, '%', 702, 'Platform Admin 15 Oct 2026: "Yield-based retry cap" (attempt 2 found a page 17% of the time, attempt 3 9%)', 'Waste rules', 'coverage-ai-match-prepare'),
 ('pipeline', 'waste.retry_window_days', 'Measure retry success over the last', 'The period the success rate of each attempt number is measured over.', 'number', to_jsonb(14), 1, 60, 'days', 703, 'Platform Admin 15 Oct 2026: "Yield-based retry cap"', 'Waste rules', 'coverage-ai-match-prepare'),
 ('pipeline', 'waste.retry_min_sample', 'Least attempts before a success rate counts', 'Below this many recent attempts an attempt number is still tried.', 'number', to_jsonb(200), 10, 10000, 'attempts', 704, 'Platform Admin 15 Oct 2026: "Yield-based retry cap"', 'Waste rules', 'coverage-ai-match-prepare'),
 ('pipeline', 'waste.retry_max_attempts', 'Most attempts: AI course-page matching', 'The most attempts at finding a course page with AI, whatever the success rate.', 'number', to_jsonb(3), 1, 5, 'attempts', 705, 'CF-247 15 Oct 2026: the 3 that was written into the job', 'Waste rules', 'coverage-ai-match-prepare'),
 ('pipeline', 'waste.flipflop_max_changes', 'Freeze a value changed automatically more than', 'A course value changed automatically more than this many times in the window (two writers disagreeing) is frozen as it is, left out of automatic updates and flagged for review.', 'number', to_jsonb(3), 2, 20, 'changes', 706, 'Platform Admin 15 Oct 2026: waste rules (106 courses changed about 33 times each in 4 days)', 'Waste rules', 'waste-guard job'),
 ('pipeline', 'waste.flipflop_window_days', 'Count automatic changes over the last', 'The window for the flip-flop rule.', 'number', to_jsonb(7), 1, 30, 'days', 707, 'Platform Admin 15 Oct 2026: waste rules', 'Waste rules', 'waste-guard job'),
 ('pipeline', 'waste.page_reuse_hours', 'Use a stored copy of a scholarship page read within', 'A page read within this time is not read again for another candidate or model step; the stored copy is used. 0 = always read again.', 'number', to_jsonb(24), 0, 168, 'hours', 708, 'Platform Admin 15 Oct 2026: "No repeat reads unchanged"', 'Waste rules', 'scholarship-ai (svc_scholarship_ai_next)'),
 ('pipeline', 'enrich.focus_top_n', 'Search for course pages only at the top Australian providers by gaps', 'Course-page search, site mapping and AI page matching run only for this many Australian providers with the most missing English and intakes. Other Australian providers keep their register data and are flagged. New Zealand and Canada are not limited. 0 = all providers.', 'number', to_jsonb(50), 0, 2000, 'providers', 709, 'Platform Admin 15 Oct 2026: "Top 50 by adapter, flag the tail"', 'Waste rules', 'course-link-search-worker, coverage-discover, coverage-ai-match-prepare')
on conflict do nothing;

-- 2 Records
create table if not exists pipeline.enrichment_flags (
  id bigserial primary key,
  entity text not null,
  entity_key text not null,
  provider_id uuid,
  field text not null default '',
  reason_code text not null,
  reason text not null,
  source text not null,
  flagged_at timestamptz not null default now(),
  cleared_at timestamptz,
  unique (entity, entity_key, field, reason_code));
comment on table pipeline.enrichment_flags is 'CF-247 15 Oct 2026: what the waste rules stopped (job paused, value frozen, page not found after the useful attempts, provider outside the focus list), with why. cleared_at is set when it no longer applies.';
create table if not exists pipeline.job_input_marks (
  job_key text primary key,
  last_input_at timestamptz,
  last_full_at timestamptz,
  last_run_at timestamptz,
  last_result jsonb,
  runs_done bigint not null default 0,
  runs_skipped bigint not null default 0,
  started_at timestamptz not null default now());
comment on table pipeline.job_input_marks is 'CF-247 15 Oct 2026: newest input each input-driven job has seen, and when it last did a full check.';
create table if not exists pipeline.job_idle_watch (
  jobname text primary key,
  output_sql text not null,
  input_sql text not null,
  note text,
  paused_at timestamptz,
  resumed_at timestamptz,
  last_checked_at timestamptz,
  last_output bigint,
  last_input bigint);
comment on table pipeline.job_idle_watch is 'CF-247 15 Oct 2026: jobs the waste guard pauses when they produce nothing and nothing waits (output_sql takes $1 = since; input_sql counts waiting work). Only jobs it paused are resumed.';
create table if not exists pipeline.enrich_focus_providers (
  provider_id uuid primary key references catalogue.providers(id),
  rank integer not null,
  gaps integer not null,
  in_focus boolean not null,
  set_at timestamptz not null default now());
comment on table pipeline.enrich_focus_providers is 'CF-247 15 Oct 2026: Australian providers ranked by missing English and intakes; in_focus = within enrich.focus_top_n.';
alter table pipeline.enrichment_flags enable row level security;
alter table pipeline.job_input_marks enable row level security;
alter table pipeline.job_idle_watch enable row level security;
alter table pipeline.enrich_focus_providers enable row level security;
revoke all on pipeline.enrichment_flags, pipeline.job_input_marks, pipeline.job_idle_watch, pipeline.enrich_focus_providers from anon, authenticated;
create index if not exists enrichment_flags_open_idx on pipeline.enrichment_flags (reason_code) where cleared_at is null;
create index if not exists scholarship_ai_extractions_url_at_idx on pipeline.scholarship_ai_extractions (url, at desc);
create index if not exists adapter_overwrite_changes_at_idx on pipeline.adapter_overwrite_changes (at);

-- 3 Rules
CREATE OR REPLACE FUNCTION security.retry_cap_v1(p_kind text)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_max int := greatest(1, security.pipeline_num_v1('waste.retry_max_attempts', 3)::int);
        v_min numeric := security.pipeline_num_v1('waste.retry_min_yield_pct', 15);
        v_days int := security.pipeline_num_v1('waste.retry_window_days', 14)::int;
        v_sample int := security.pipeline_num_v1('waste.retry_min_sample', 200)::int;
        v_n bigint; v_ok bigint;
begin
  -- the most attempts worth making: attempt k is made while its recent success rate is at least the setting (or it has too few recent cases)
  if p_kind <> 'ai_match' then return v_max; end if;
  for k in 2 .. v_max loop
    select count(*), count(*) filter (where q.state = 'chosen') into v_n, v_ok
      from pipeline.coverage_ai_match q
     where q.attempt = k and q.state in ('chosen', 'none') and q.decided_at > now() - make_interval(days => v_days);
    if v_n >= v_sample and 100.0 * v_ok / v_n < v_min then return k - 1; end if;
  end loop;
  return v_max;
end $function$;

CREATE OR REPLACE FUNCTION security.enrich_focus_v1(p_provider_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- page search runs for every provider when the setting is 0, for providers outside Australia, and for the Australian focus providers
  select security.pipeline_num_v1('enrich.focus_top_n', 50) = 0
      or coalesce(security.coverage_country(p_provider_id), '') <> 'AU'
      or exists (select 1 from pipeline.enrich_focus_providers f where f.provider_id = p_provider_id and f.in_focus)
$function$;

CREATE OR REPLACE FUNCTION security.enrich_focus_refresh_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_top int := security.pipeline_num_v1('enrich.focus_top_n', 50)::int; v_n int;
begin
  insert into pipeline.enrich_focus_providers(provider_id, rank, gaps, in_focus, set_at)
  select g.provider_id, g.rk, g.gaps, g.rk <= v_top, now()
    from (select d.provider_id, (count(*) filter (where not d.has_english) + count(*) filter (where not d.has_intake))::int gaps,
                 row_number() over (order by count(*) filter (where not d.has_english) + count(*) filter (where not d.has_intake) desc, d.provider_id)::int rk
            from search.course_documents d
           where d.country_code = 'AU' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id)
           group by d.provider_id) g
  on conflict (provider_id) do update set rank = excluded.rank, gaps = excluded.gaps, in_focus = excluded.in_focus, set_at = now();
  update pipeline.enrich_focus_providers f set in_focus = false, set_at = now()
   where f.in_focus and f.set_at < now();  -- providers not ranked in this refresh
  select count(*) into v_n from pipeline.enrich_focus_providers where in_focus;
  return v_n;
end $function$;

CREATE OR REPLACE FUNCTION security.own_page_value_v1(p_course_id uuid, p_field text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- the course's own page, read by an adapter cleared to admit this field, holds a value: that reading wins over a value taken from another course
  select exists (
    select 1 from pipeline.coverage_course_pages pg
      join pipeline.uni_adapters u on u.provider_id = pg.provider_id and u.enabled and u.admit and p_field = any (u.admit_fields)
     where pg.course_id = p_course_id and pg.read_status = 'read' and pg.identity_basis is not null
       and case p_field
             when 'delivery' then coalesce(security.delivery_mode_from_text(pg.candidates->'adapter_extra'->>'mode'),
                                           security.delivery_mode_from_location(coalesce(pg.candidates->'adapter_extra'->>'location', pg.candidates->'adapter_extra'->>'campus'))) is not null
             when 'intakes' then pg.candidates->>'intakes_by' = 'adapter' and jsonb_array_length(coalesce(pg.candidates->'intakes', '[]'::jsonb)) > 0
             when 'fee' then pg.candidates->>'fee_by' = 'adapter' and nullif(pg.candidates->'fee'->>'value', '') is not null
             else false end)
$function$;

CREATE OR REPLACE FUNCTION security.admit_input_mark_v1()
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- the newest change any admit job depends on: pages read, adapters and their admission, checked values, exclusions, locks, review decisions,
  -- courses and providers (lifecycle, Published switch)
  select greatest(
    (select max(pg.read_at) from pipeline.coverage_course_pages pg),
    (select max(greatest(u.updated_at, u.admit_changed_at)) from pipeline.uni_adapters u),
    (select max(i.created_at) from pipeline.layer3_interpretations i where i.status = 'validated'),
    (select max(x.set_at) from pipeline.uni_adapter_exclusions x),
    (select max(x.set_at) from pipeline.uni_adapter_delivery_exclusions x),
    (select max(k.set_at) from pipeline.manual_locks k),
    (select max(r.decided_at) from pipeline.layer4_review_items r),
    (select max(c.updated_at) from catalogue.courses c),
    (select max(p.updated_at) from catalogue.providers p),
    '-infinity'::timestamptz)
$function$;

CREATE OR REPLACE FUNCTION security.coverage_admission_gated_v1(p_key text, p_limit integer, p_extractor text, p_attributes text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare m pipeline.job_input_marks%rowtype; v_in timestamptz := security.admit_input_mark_v1(); v jsonb; v_more boolean;
        v_full int := security.pipeline_num_v1('waste.admit_full_check_hours', 6)::int;
begin
  insert into pipeline.job_input_marks(job_key) values (p_key) on conflict do nothing;
  select * into m from pipeline.job_input_marks where job_key = p_key for update;
  if not coalesce((m.last_result->>'more')::boolean, true) and m.last_input_at is not null and v_in <= m.last_input_at
     and m.last_full_at > now() - make_interval(hours => v_full) then
    update pipeline.job_input_marks set runs_skipped = runs_skipped + 1, last_run_at = now() where job_key = p_key;
    return jsonb_build_object('skipped', 'no new input');
  end if;
  v := security.coverage_admission_apply_v1(p_limit, p_extractor, p_attributes);
  v_more := coalesce((v->>'written')::int, 0) >= p_limit;
  update pipeline.job_input_marks set last_input_at = v_in, last_full_at = now(), last_run_at = now(), last_result = v || jsonb_build_object('more', v_more),
         runs_done = runs_done + 1 where job_key = p_key;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION security.adapter_overwrite_gated_v1(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare m pipeline.job_input_marks%rowtype; v_in timestamptz := security.admit_input_mark_v1(); v jsonb; v_more boolean;
        v_full int := security.pipeline_num_v1('waste.admit_full_check_hours', 6)::int;
begin
  insert into pipeline.job_input_marks(job_key) values ('adapter-overwrite') on conflict do nothing;
  select * into m from pipeline.job_input_marks where job_key = 'adapter-overwrite' for update;
  if not coalesce((m.last_result->>'more')::boolean, true) and m.last_input_at is not null and v_in <= m.last_input_at
     and m.last_full_at > now() - make_interval(hours => v_full) then
    update pipeline.job_input_marks set runs_skipped = runs_skipped + 1, last_run_at = now() where job_key = 'adapter-overwrite';
    return jsonb_build_object('skipped', 'no new input');
  end if;
  v := security.adapter_overwrite_v1(p_limit);
  v_more := coalesce((v->>'replaced')::int, 0) >= p_limit;
  update pipeline.job_input_marks set last_input_at = v_in, last_full_at = now(), last_run_at = now(), last_result = v || jsonb_build_object('more', v_more),
         runs_done = runs_done + 1 where job_key = 'adapter-overwrite';
  return v;
end $function$;

CREATE OR REPLACE FUNCTION security.waste_idle_guard_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare w record; v_jobid bigint; v_active boolean; v_out bigint; v_inp bigint; v jsonb := '[]'::jsonb;
        v_hours int := security.pipeline_num_v1('waste.idle_pause_hours', 24)::int;
begin
  for w in select * from pipeline.job_idle_watch order by jobname loop
    select j.jobid, j.active into v_jobid, v_active from cron.job j where j.jobname = w.jobname;
    continue when v_jobid is null;
    execute w.output_sql into v_out using now() - make_interval(hours => v_hours);
    execute w.input_sql into v_inp;
    update pipeline.job_idle_watch set last_checked_at = now(), last_output = v_out, last_input = v_inp where jobname = w.jobname;
    if v_active and coalesce(v_out, 0) = 0 and coalesce(v_inp, 0) = 0 and coalesce(w.resumed_at, '-infinity') < now() - make_interval(hours => v_hours) then
      perform cron.alter_job(v_jobid, active := false);
      update pipeline.job_idle_watch set paused_at = now() where jobname = w.jobname;
      insert into pipeline.enrichment_flags(entity, entity_key, field, reason_code, reason, source)
      values ('job', w.jobname, '', 'idle_paused', format('Paused: no output for %s hours and nothing waiting. %s', v_hours, coalesce(w.note, '')), 'waste-guard')
      on conflict (entity, entity_key, field, reason_code) do update set reason = excluded.reason, flagged_at = now(), cleared_at = null;
      v := v || jsonb_build_object('paused', w.jobname);
    elsif not v_active and w.paused_at is not null and coalesce(v_inp, 0) > 0 then
      -- only a job this guard paused is switched on again
      perform cron.alter_job(v_jobid, active := true);
      update pipeline.job_idle_watch set paused_at = null, resumed_at = now() where jobname = w.jobname;
      update pipeline.enrichment_flags set cleared_at = now() where entity = 'job' and entity_key = w.jobname and reason_code = 'idle_paused' and cleared_at is null;
      v := v || jsonb_build_object('resumed', w.jobname);
    end if;
  end loop;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION security.waste_flipflop_guard_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_n int := 0; v_field text; v_reason text;
        v_max int := security.pipeline_num_v1('waste.flipflop_max_changes', 3)::int;
        v_since timestamptz := greatest(now() - make_interval(days => security.pipeline_num_v1('waste.flipflop_window_days', 7)::int),
                                        coalesce((select m.started_at from pipeline.job_input_marks m where m.job_key = 'flipflop-guard'), now()));
begin
  for r in select c.course_id, c.field, max(c.provider_id::text)::uuid provider_id, count(*) n
             from pipeline.adapter_overwrite_changes c where c.at > v_since
            group by c.course_id, c.field having count(*) > v_max loop
    v_field := case r.field when 'english_ielts' then 'english' else r.field end;
    v_reason := format('automatic: changed %s times since %s by automatic writers that disagree; kept as it is and left out of automatic updates (waste rule, CF-247 15 Oct 2026)',
                       r.n, to_char(v_since at time zone 'Australia/Melbourne', 'DD Mon HH24:MI'));
    if v_field = 'delivery' then
      insert into pipeline.uni_adapter_delivery_exclusions(course_id, provider_id, active, reason) values (r.course_id, r.provider_id, true, v_reason)
      on conflict (course_id) do nothing;
    elsif v_field in ('intakes', 'english', 'fee') then
      insert into pipeline.uni_adapter_exclusions(course_id, field, provider_id, active, reason) values (r.course_id, v_field, r.provider_id, true, v_reason)
      on conflict (course_id, field) do nothing;
    else
      continue;
    end if;
    insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
    values ('course', r.course_id::text, r.provider_id, v_field, 'flip_flop', v_reason, 'waste-guard')
    on conflict (entity, entity_key, field, reason_code) do nothing;
    if found then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $function$;

CREATE OR REPLACE FUNCTION security.enrichment_flags_refresh_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_tail int := 0; v_nf int := 0; v_cap int := security.retry_cap_v1('ai_match'); v_on boolean := security.pipeline_num_v1('enrich.focus_top_n', 50) > 0;
begin
  -- Australian courses of providers outside the focus list that still lack a course page, English or intakes: not searched further
  if v_on then
    insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
    select 'course', d.course_id::text, d.provider_id, 'course_page', 'outside_focus',
           'Not searched further: the provider is outside the top Australian providers by gaps (Pipeline settings › Waste rules); register data only', 'waste-guard'
      from search.course_documents d
     where d.country_code = 'AU' and (d.official_course_url is null or not d.has_english or not d.has_intake)
       and not security.enrich_focus_v1(d.provider_id)
    on conflict (entity, entity_key, field, reason_code) do update set cleared_at = null where pipeline.enrichment_flags.cleared_at is not null;
    get diagnostics v_tail = row_count;
  end if;
  update pipeline.enrichment_flags f set cleared_at = now()
   where f.reason_code = 'outside_focus' and f.cleared_at is null and (not v_on or security.enrich_focus_v1(f.provider_id));
  -- courses whose page was not found after the useful AI attempts
  insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
  select 'course', q.course_id::text, max(q.provider_id::text)::uuid, 'official_url', 'page_not_found',
         format('No course page found after %s AI attempt(s) (no further candidates, or later attempts rarely succeed: Pipeline settings › Waste rules)', count(*)), 'waste-guard'
    from pipeline.coverage_ai_match q
   where not exists (select 1 from pipeline.coverage_course_pages p where p.course_id = q.course_id and p.status = 'bound')
   group by q.course_id
  having (count(*) >= v_cap or bool_or(q.state = 'no_candidates')) and bool_and(q.state in ('none', 'no_candidates', 'error'))
  on conflict (entity, entity_key, field, reason_code) do nothing;
  get diagnostics v_nf = row_count;
  update pipeline.enrichment_flags f set cleared_at = now()
   where f.reason_code = 'page_not_found' and f.cleared_at is null
     and exists (select 1 from pipeline.coverage_course_pages p where p.course_id::text = f.entity_key and p.status = 'bound');
  return jsonb_build_object('outside_focus', v_tail, 'page_not_found', v_nf);
end $function$;

CREATE OR REPLACE FUNCTION security.waste_guard_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return jsonb_build_object('idle', security.waste_idle_guard_v1(), 'frozen', security.waste_flipflop_guard_v1(), 'flags', security.enrichment_flags_refresh_v1());
end $function$;

revoke execute on function security.retry_cap_v1(text), security.enrich_focus_v1(uuid), security.enrich_focus_refresh_v1(), security.own_page_value_v1(uuid, text),
  security.admit_input_mark_v1(), security.coverage_admission_gated_v1(text, integer, text, text[]), security.adapter_overwrite_gated_v1(integer),
  security.waste_idle_guard_v1(), security.waste_flipflop_guard_v1(), security.enrichment_flags_refresh_v1(), security.waste_guard_v1() from public, anon, authenticated;


CREATE OR REPLACE FUNCTION security.coverage_admission_apply_v1(p_limit integer DEFAULT 300, p_extractor text DEFAULT 'coverage-sweep-v0.5.4'::text, p_attributes text[] DEFAULT ARRAY['official_url'::text, 'english'::text])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security', 'search'
AS $function$
declare r record; v_src uuid; v_ok int:=0; v_err int:=0; v_l4 int:=0; v_courses uuid[]:='{}'; v_before jsonb; v_after jsonb; v_payload jsonb; v_last text;
begin
  drop table if exists _adm;
  create temp table _adm on commit drop as select * from security.coverage_admission_plan_v1(p_extractor) where action in ('write','differs') and attribute=any(p_attributes);
  if not exists (select 1 from _adm) then return jsonb_build_object('written',0,'layer4',0); end if;

  insert into pipeline.course_fact_source_qualifications(source_id,country_id,source_key,source_class,authority_name,provider_cricos,admitted_domains,mapping_strategy,evidence_strategy,qualification_status,notes,metadata)
  select distinct on (s.id) s.id, s.country_id, 'au_'||lower(a.provider_cricos)||'_coverage_sweep','provider_first_party',
         coalesce(p.display_name,p.canonical_name), upper(a.provider_cricos), array['official_course_url','english_requirement','intake'],
         'course page accepted only when it prints the course''s CRICOS code',
         'page stored gzipped as evidence with its SHA-256; values written only where the course has none',
         'bounded','Decision 163 admission rule (Platform Admin 29 Sep 2026)',
         jsonb_build_object('decision','Decision 163','apply_admitted',true,'search_admitted',true,'identity_authority',false,'change_control_ref','CF-CHG-20260915-247')
    from _adm a join catalogue.providers p on p.id=a.provider_id
    cross join lateral (select security.coverage_sweep_source(a.provider_id) id) x
    join pipeline.sources s on s.id=x.id
   where a.action='write' and a.provider_cricos is not null
     and not exists (select 1 from pipeline.course_fact_source_qualifications q where q.source_id=s.id and q.provider_cricos=upper(a.provider_cricos));

  insert into search.enrichment_source_gates(projection_code,domain_code,source_id,gate_status,approval_ref,approved_at,created_at,updated_at)
  select distinct 'courses', d, security.coverage_sweep_source(a.provider_id), 'approved',
         'CF-CHG-20260915-247; Decision 163 admission rule; Platform Admin approval 29 Sep 2026 09:56 IST', now(), now(), now()
    from _adm a cross join unnest(array_remove(array['official_course_url', case when 'english'=any(p_attributes) then 'course_english' end, case when 'intakes'=any(p_attributes) then 'course_intake' end],null)) d
   where a.action='write'
     and not exists (select 1 from search.enrichment_source_gates g where g.projection_code='courses' and g.domain_code=d and g.source_id=security.coverage_sweep_source(a.provider_id));

  v_before:=security.consumer_api_snapshot_v1();
  for r in select a.course_id, a.provider_id, a.provider_cricos, a.course_cricos, a.evidence_id, a.content_hash, a.page_url,
                  jsonb_object_agg(a.attribute, a.proposed) props
             from _adm a where a.action='write'
            group by 1,2,3,4,5,6,7 order by md5(a.course_id::text||clock_timestamp()::text) limit greatest(1,least(coalesce(p_limit,300),1000)) loop
    v_payload:='{}'::jsonb;
    if r.props ? 'official_url' then v_payload:=v_payload||jsonb_build_object('course_url',r.props->'official_url'->>'course_url','link_type','official_course','audience','international'); end if;
    if r.props ? 'english' and not security.uni_adapter_excluded(r.course_id, 'english') then v_payload:=v_payload||jsonb_build_object('english_requirements',r.props->'english'->'english_requirements'); end if;
    if r.props ? 'intakes' and not security.uni_adapter_excluded(r.course_id, 'intakes') then v_payload:=v_payload||jsonb_build_object('intakes',r.props->'intakes'->'intakes'); end if;
    begin
      if r.provider_cricos is null or r.course_cricos is null then
        perform security.coverage_apply_course_v1(r.course_id, security.coverage_sweep_source(r.provider_id), r.evidence_id, r.page_url, r.content_hash, v_payload);
      else
      perform public.svc_coursefacts_apply_record(security.coverage_sweep_source(r.provider_id), r.evidence_id, r.provider_cricos, r.course_cricos,
              'coverage:'||r.course_id, r.page_url, r.content_hash, v_payload, true);
      end if;
      v_ok:=v_ok+1; v_courses:=v_courses||r.course_id;
    exception when others then v_err:=v_err+1; v_last:=left(sqlerrm,200);
    end;
  end loop;

  insert into pipeline.layer4_review_items(entity_type,entity_id,field_code,evidence_id,before_value,proposed_value,layer2_state,layer3_state,status,escalation_reason,change_control_ref)
  select 'course', a.course_id,
         case a.attribute when 'official_url' then 'official_course_url' when 'english' then 'course_english' else 'course_intake' end,
         a.evidence_id, a.current, a.proposed, jsonb_build_object('source','coverage sweep','page',a.page_url), '{}'::jsonb, 'pending',
         case a.attribute
           when 'official_url' then 'The course page that shows this course''s CRICOS code is a different address from the official page we hold. Please check which page is current.'
           when 'english' then 'The course page gives a different English score from the one we hold. Please check the page and confirm the requirement.'
           else 'The course page lists different intake months from the ones we hold. Please check the page and confirm the intakes.' end,
         'CF-CHG-20260915-247'
    from _adm a
   where a.action='differs'
     and not exists (select 1 from pipeline.layer4_review_items i where i.entity_type='course' and i.entity_id=a.course_id and i.status='pending'
                       and i.field_code=case a.attribute when 'official_url' then 'official_course_url' when 'english' then 'course_english' else 'course_intake' end)
     -- CF-247 15 Oct (waste rules): the same proposal is not raised again while an identical one was superseded within the window (it was raised 144 times a day)
     and not exists (select 1 from pipeline.layer4_review_items i where i.entity_type='course' and i.entity_id=a.course_id and i.status='superseded'
                       and i.field_code=case a.attribute when 'official_url' then 'official_course_url' when 'english' then 'course_english' else 'course_intake' end
                       and i.proposed_value=a.proposed and i.decided_at > now() - make_interval(days => security.pipeline_num_v1('waste.flipflop_window_days', 7)::int));
  get diagnostics v_l4=row_count;

  if cardinality(v_courses)>0 then
    perform search.refresh_course_enrichment_scoped_v1(v_courses,true);
    v_after:=security.consumer_api_snapshot_v1();
    insert into pipeline.consumer_api_baselines(label,snapshot) values
      ('before coverage admission batch ('||cardinality(v_courses)||' courses, Decision 163)',v_before),
      ('after coverage admission batch ('||cardinality(v_courses)||' courses, Decision 163)',v_after);
  end if;
  return jsonb_build_object('written',v_ok,'errors',v_err,'last_error',v_last,'layer4',v_l4);
end $function$;

CREATE OR REPLACE FUNCTION security.coverage_ai_match_prepare_v1(p_providers integer DEFAULT 4, p_courses integer DEFAULT 300)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security'
AS $function$
declare r record; v jsonb := '[]'::jsonb; v_n int; v_cap int := security.retry_cap_v1('ai_match');  -- CF-247 15 Oct: attempts worth making (Waste rules)
begin
  for r in
    with missing as (
      select co.provider_id, count(*) n
        from catalogue.courses co
        left join pipeline.coverage_course_pages p on p.course_id = co.id
       where co.lifecycle_status = 'active'
         and security.enrich_focus_v1(co.provider_id)  -- CF-247 15 Oct: focus providers only (Waste rules)
         and (p.course_id is null or p.status = 'mismatch')
         and not exists (select 1 from pipeline.coverage_ai_match q where q.course_id = co.id and q.state in ('ready', 'leased', 'no_candidates'))
         and (select count(*) from pipeline.coverage_ai_match q where q.course_id = co.id) < v_cap
       group by 1)
    select m.provider_id, m.n from missing m
     where exists (select 1 from pipeline.coverage_provider_urls u where u.provider_id = m.provider_id)
     order by coalesce((select pp.rank from pipeline.provider_priority pp where pp.provider_id = m.provider_id), 100000), m.n desc
     limit greatest(1, least(p_providers, 500))
  loop
    insert into pipeline.coverage_ai_match(course_id, provider_id, attempt, state, candidates)
    with c as (
      select co.id course_id, lower(coalesce(co.course_code, '')) code,
             security.coverage_text_tokens(regexp_replace(co.canonical_title, '\(\s*level\s+\d+\s*\)', '', 'i')) tok,
             (select count(*) from pipeline.coverage_ai_match q where q.course_id = co.id) prev
        from catalogue.courses co
        left join pipeline.coverage_course_pages p on p.course_id = co.id
       where co.provider_id = r.provider_id and co.lifecycle_status = 'active'
         and (p.course_id is null or p.status = 'mismatch')
         and not exists (select 1 from pipeline.coverage_ai_match q where q.course_id = co.id and q.state in ('ready', 'leased', 'no_candidates'))
         and (select count(*) from pipeline.coverage_ai_match q where q.course_id = co.id) < v_cap
       order by coalesce(co.open_to_international, false) desc, co.id
       limit greatest(1, least(p_courses, 1000))),
    tried as (
      select p.course_id, p.url from pipeline.coverage_course_pages p join c using (course_id)
      union select q.course_id, q.chosen_url from pipeline.coverage_ai_match q join c using (course_id) where q.chosen_url is not null),
    u as (
      select url, title, tokens, title_tokens, cardinality(tokens) ns, cardinality(title_tokens) nt
        from pipeline.coverage_provider_urls where provider_id = r.provider_id
         and url !~* '/(inherent-requirements|entry-requirements|admission-requirements|english-requirements|fees?|tuition-fees?|scholarships?|apply|how-to-apply|applying|careers?|credit|recognition-of-prior-learning|timetables?|news|events?|stories|blog|alumni|contact|faqs?)(/|$)'
         and url !~* '\.(pdf|jpe?g|png|gif|svg|docx?|xlsx?|zip)(\?|$)'),
    ct as (select course_id, cardinality(tok) nc, t from c, unnest(tok) t),
    ut as (select url, ns n, t from u, unnest(tokens) t union all select url, nt, t from u, unnest(title_tokens) t),
    m as (select ct.course_id, ut.url, max(ct.nc) nc, max(ut.n) nu, count(*) hits from ct join ut using (t) group by 1, 2),
    s as (select m.course_id, m.url, max(2.0 * hits / nullif(nc + nu, 0)) sc from m group by 1, 2
          union all
          select c.course_id, u.url, 2.0 from c join u on length(c.code) >= 6 and position(c.code in lower(u.url)) > 0),
    best as (select s.course_id, s.url, max(s.sc) sc from s where not exists (select 1 from tried t where t.course_id = s.course_id and t.url = s.url) group by 1, 2),
    rk as (select b.*, row_number() over (partition by b.course_id order by b.sc desc, length(b.url)) n from best b)
    select c.course_id, r.provider_id, c.prev + 1,
           case when count(rk.url) = 0 then 'no_candidates' else 'ready' end,
           coalesce(jsonb_agg(jsonb_build_object('url', rk.url, 'title', left(coalesce(u.title, ''), 160)) order by rk.n) filter (where rk.url is not null), '[]'::jsonb)
      from c left join rk on rk.course_id = c.course_id and rk.n <= 25
      left join u on u.url = rk.url
     group by c.course_id, c.prev;
    get diagnostics v_n = row_count;
    v := v || jsonb_build_object('provider_id', r.provider_id, 'prepared', v_n);
  end loop;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_course_link_search_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_on boolean; v_cap numeric; v_used numeric; v_lim int := greatest(1, least(coalesce(p_limit, 40), 200)); v jsonb; v_stopped uuid[];
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select enabled, monthly_credit_cap into v_on, v_cap from pipeline.course_link_search_settings where id = 1;
  select coalesce(sum(units), 0) into v_used from pipeline.coverage_vendor_usage where purpose = 'course_link_search' and at >= date_trunc('month', now());
  if not coalesce(v_on, false) or v_used + 2 * v_lim > v_cap then return '[]'::jsonb; end if;
  -- v2.15.262: inside the day's Firecrawl share for course search, and not for universities whose search has stopped
  v_lim := least(v_lim, floor(security.fc_budget_left_v1('course_link_search') / 2)::int);
  if v_lim < 1 then return '[]'::jsonb; end if;
  v_stopped := array(select x.provider_id from security.fc_search_stopped_v1() x);
  with pick as (
    select s.course_id, s.provider_id, s.stage, c.course_code, c.canonical_title, rc.search_domain
      from pipeline.course_link_search s join catalogue.courses c on c.id = s.course_id
      join pipeline.course_link_recipes rc on rc.provider_id = s.provider_id and rc.active
      left join pipeline.provider_priority pp on pp.provider_id = s.provider_id
     where s.state = 'queued'
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
       -- v2.15.255: while Firecrawl is for target universities only, take only their searches (others were refused and starved the queue)
       and (not coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true)
            or exists (select 1 from pipeline.firecrawl_target_cache tc where tc.provider_id = s.provider_id and tc.included))
       and s.provider_id <> all (v_stopped)
       and security.enrich_focus_v1(s.provider_id)  -- CF-247 15 Oct: focus providers only (Waste rules)
       -- v2.15.265: never a search limited to a directory site
       and not security.third_party_host_v1('https://' || rc.search_domain)
     -- v2.15.265: top-50, Australian 30+ courses, overseas, small providers; CRICOS-code searches first within each
     order by security.fc_provider_tier_v1(s.provider_id), (s.stage <> 'cricos'), coalesce(pp.rank, 100000), md5(s.course_id::text || to_char(now(), 'YYYYMMDDHH24MI'))
     limit v_lim
     for update of s skip locked),
  upd as (
    update pipeline.course_link_search s set state = 'sent', sent_at = now(), req_id = null,
           query = case p.stage when 'cricos' then '"' || p.course_code || '" site:' || p.search_domain
                                else case when security.coverage_country(p.provider_id) = 'CA'
                                     then trim(regexp_replace(regexp_replace(regexp_replace(p.canonical_title, '\s*\([^)]*\)', ' ', 'g'), '\s+-\s+(UBCV|UBCO|Major|Honours|Open Learning)\M.*$', '', 'i'), '[:"]+', ' ', 'g')) || ' site:' || p.search_domain
                                     else '"' || replace(regexp_replace(p.canonical_title, '\s*\(\s*Level\s+\d{1,2}\s*\)\s*$', '', 'i'), '"', '') || '" site:' || p.search_domain end end
      from pick p where s.course_id = p.course_id
    returning s.course_id, s.provider_id, s.stage, s.query)
  select coalesce(jsonb_agg(jsonb_build_object('course_id', course_id, 'provider_id', provider_id, 'stage', stage, 'query', query)), '[]'::jsonb) into v from upd;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_coverage_discovery_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select d.provider_id from pipeline.coverage_provider_discovery d
     where (d.status='pending' or (d.status in ('mapped','failed') and d.next_due_at<=now())) and coalesce(d.leased_until,'-infinity')<now() and d.attempts<3
       and security.enrich_focus_v1(d.provider_id)  -- CF-247 15 Oct: focus providers only (Waste rules)
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by (select count(*) from catalogue.courses c where c.provider_id=d.provider_id and c.lifecycle_status='active') desc
     limit greatest(1,least(coalesce(p_limit,5),20)) for update skip locked),
  upd as (update pipeline.coverage_provider_discovery d set leased_until=now()+interval '10 minutes', attempts=d.attempts+1, updated_at=now()
            from pick where d.provider_id=pick.provider_id returning d.provider_id, d.website)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id',u.provider_id,'website',u.website,
           'courses',(select count(*) from catalogue.courses c where c.provider_id=u.provider_id and c.lifecycle_status='active'))),'[]'::jsonb) into v from upd u;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION security.exit_awards_apply_v2(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_src uuid; v_hash text; v_fee record; v_itk text[]; v_payload jsonb; v_mode text; v_done int := 0; v_err int := 0; v_skipped int := 0; v_last text; v_courses uuid[] := '{}'; v_af text[];
begin
  select u.admit_fields into v_af from pipeline.uni_adapters u where u.provider_id = p_provider_id and u.enabled and u.admit and 'exit_awards' = any (u.admit_fields);
  if v_af is null then
    return jsonb_build_object('ok', false, 'note', 'exit awards are not admitted for this university'); end if;
  v_src := security.coverage_sweep_source(p_provider_id);
  for r in
    select x.*, pc.course_url parent_url, pc.delivery_mode parent_mode, ch.delivery_mode child_mode
      from pipeline.course_exit_awards x join catalogue.courses pc on pc.id = x.parent_course_id join catalogue.courses ch on ch.id = x.child_course_id and ch.lifecycle_status = 'active'
     where x.provider_id = p_provider_id and x.active and x.evidence_id is not null
       and not security.layer4_entity_or_parent_blocked('course', x.child_course_id, 'operational')
  loop
    if r.register_check = 'fail' and r.set_by <> 'hand' then v_skipped := v_skipped + 1; continue; end if;
    begin
      select e.content_hash into v_hash from pipeline.evidence_artifacts e where e.id = r.evidence_id;
      v_payload := jsonb_build_object('course_url', r.page_url);
      select null::numeric amount, null::int fee_year, null::text currency_code into v_fee;
      if 'fee' = any (v_af) and not security.own_page_value_v1(r.child_course_id, 'fee') then  -- CF-247 15 Oct: the course's own page wins
        select f.amount, f.fee_year, f.currency_code into v_fee from catalogue.course_fees f
         where f.course_id = r.parent_course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and f.amount > 0
         order by f.fee_year desc nulls last, f.updated_at desc nulls last limit 1;
      end if;
      if v_fee.amount is not null and not security.uni_adapter_excluded(r.child_course_id, 'fee')
         and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.child_course_id and k.field in ('tuition', 'fee', 'fees'))
         and (select f.amount from catalogue.course_fees f where f.course_id = r.child_course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and coalesce(f.fee_year, 0) = coalesce(v_fee.fee_year, 0) order by f.updated_at desc nulls last limit 1) is distinct from v_fee.amount then
        update catalogue.course_fees set status = 'superseded', updated_at = now() where course_id = r.child_course_id and status = 'active' and fee_type = 'provider_current_tuition' and audience = 'international' and source_id is not null and coalesce(fee_year, 0) = coalesce(v_fee.fee_year, 0) and amount <> v_fee.amount;
        v_payload := v_payload || jsonb_build_object('fee_amount', v_fee.amount, 'fee_year', v_fee.fee_year, 'currency_code', v_fee.currency_code, 'fee_basis', 'annual', 'audience', 'international',
                       'fee_notes', case r.link_type when 'nested_award' then 'Award within the course on this page (' || r.exit_years || ' years of full-time study): annual fee as the course, whole fee ' || round(v_fee.amount * r.exit_years, 2) || ' (annual x ' || r.exit_years || ')'
                                    else 'Exit award after ' || r.exit_years || ' years of full-time study in the course on this page: annual fee as the course, whole fee ' || round(v_fee.amount * r.exit_years, 2) || ' (annual x ' || r.exit_years || ')' end);
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url)
          values (r.child_course_id, p_provider_id, 'fee', null, jsonb_build_object('amount', v_fee.amount, 'year', v_fee.fee_year, 'exit_award_of', r.parent_course_id, 'link_type', r.link_type, 'years', r.exit_years, 'whole_fee', round(v_fee.amount * r.exit_years, 2), 'register_check', r.register_check), r.evidence_id, r.page_url);
      end if;
      v_itk := null;
      if 'intakes' = any (v_af) and not security.own_page_value_v1(r.child_course_id, 'intakes') then  -- CF-247 15 Oct: the course's own page wins
        v_itk := (select array_agg(distinct i.intake_label order by i.intake_label) from catalogue.course_intakes i where i.course_id = r.parent_course_id and i.status = 'active');
      end if;
      if v_itk is not null and not security.uni_adapter_excluded(r.child_course_id, 'intakes')
         and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.child_course_id and k.field in ('intakes', 'intake'))
         and (select array_agg(distinct i.intake_label order by i.intake_label) from catalogue.course_intakes i where i.course_id = r.child_course_id and i.status = 'active') is distinct from v_itk then
        update catalogue.course_intakes set status = 'withdrawn' where course_id = r.child_course_id and status = 'active' and source_id is not null and intake_label <> all (v_itk);
        v_payload := v_payload || jsonb_build_object('intakes', (select jsonb_agg(jsonb_build_object('intake_label', m, 'source_intake_key', 'exit-award:' || r.child_course_id || ':' || lower(m))) from unnest(v_itk) m));
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url)
          values (r.child_course_id, p_provider_id, 'intakes', null, jsonb_build_object('months', to_jsonb(v_itk), 'exit_award_of', r.parent_course_id), r.evidence_id, r.page_url);
      end if;
      perform security.coverage_apply_course_v1(r.child_course_id, v_src, r.evidence_id, r.page_url, v_hash, v_payload);
      v_mode := case when 'delivery' = any (v_af) and not security.own_page_value_v1(r.child_course_id, 'delivery') then r.parent_mode end;  -- CF-247 15 Oct: the course's own page wins
      if v_mode is not null and r.child_mode is distinct from v_mode and not security.uni_adapter_excluded(r.child_course_id, 'delivery')
         and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.child_course_id and k.field in ('delivery_mode', 'delivery')) then
        update catalogue.courses set delivery_mode = v_mode, updated_at = now() where id = r.child_course_id;
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url)
          values (r.child_course_id, p_provider_id, 'delivery', to_jsonb(r.child_mode), jsonb_build_object('mode', v_mode, 'exit_award_of', r.parent_course_id), r.evidence_id, r.page_url);
      end if;
      update pipeline.course_exit_awards set applied_at = now(), annual_fee = v_fee.amount, fee_year = v_fee.fee_year, total_fee = round(v_fee.amount * r.exit_years, 2) where child_course_id = r.child_course_id;
      v_done := v_done + 1; v_courses := v_courses || r.child_course_id;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if cardinality(v_courses) > 0 then perform search.refresh_course_enrichment_scoped_v1(v_courses, true); end if;
  return jsonb_build_object('ok', true, 'applied', v_done, 'skipped_check_failed', v_skipped, 'errors', v_err, 'last_error', v_last);
end $function$;

CREATE OR REPLACE FUNCTION security.firecrawl_panel_refresh_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n int;
begin
  -- CF-247 15 Oct: never at the same time as the target refresh (they deadlocked on the target cache)
  if not pg_try_advisory_xact_lock(hashtext('cf247:firecrawl_targets_refresh')) then return 0; end if;
  with c as (
    select t.provider_id, jsonb_build_object('courses', count(*),
           'confirmed', count(*) filter (where pg.status = 'bound' and pg.read_status = 'read' and pg.identity_basis is not null),
           'unreadable', count(*) filter (where pg.status in ('bound', 'ambiguous') and pg.read_status in ('needs_render', 'blocked', 'fetch_failed', 'too_thin', 'robots_disallowed')),
           'no_page', count(*) filter (where pg.course_id is null or pg.status not in ('bound', 'ambiguous')),
           'adapter_confirmed', count(*) filter (where pg.read_status = 'read' and pg.identity_basis in ('adapter_code', 'adapter_title')),
           'waiting_read', count(*) filter (where pg.status = 'bound' and (pg.read_status is null or pg.read_status = 'needs_render')),
           'intakes', count(*) filter (where exists (select 1 from catalogue.course_intakes i where i.course_id = cc.id and coalesce(i.status, 'active') = 'active')),
           'english', count(*) filter (where exists (select 1 from catalogue.course_english_requirements e where e.course_id = cc.id and coalesce(e.status, 'active') = 'active')),
           'any_fee', count(*) filter (where exists (select 1 from catalogue.course_fees f where f.course_id = cc.id and coalesce(f.audience, '') ~* 'int'))) s
    from pipeline.firecrawl_target_cache t join catalogue.courses cc on cc.provider_id = t.provider_id and cc.lifecycle_status = 'active'
    left join pipeline.coverage_course_pages pg on pg.course_id = cc.id
    where t.name is not null
    group by t.provider_id
  )
  update pipeline.firecrawl_target_cache t set stats = c.s, stats_at = now() from c where c.provider_id = t.provider_id;
  get diagnostics n = row_count;
  insert into pipeline.firecrawl_panel_figures(id, backlog, refreshed_at)
    values (1, jsonb_build_object('read_page', (select count(*) from security.firecrawl_backlog_v1('read_page')), 'find_page', (select count(*) from security.firecrawl_backlog_v1('find_page'))), now())
  on conflict (id) do update set backlog = excluded.backlog, refreshed_at = now() where pipeline.firecrawl_panel_figures.id = 1;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_ai_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb; v_reuse int := security.pipeline_num_v1('waste.page_reuse_hours', 24)::int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  -- v2.15.271 (Platform Admin, 14 Oct 2026): pages on a directory site, and providers whose scholarship search is Off, are closed, not read
  update pipeline.scholarship_ai_queue q
     set state = 'failed', done_at = now(), leased_until = null,
         skip_reason = case when security.third_party_host_v1(q.url) then 'directory site' else 'scholarship search off for this provider' end
   where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now()))
     and (security.third_party_host_v1(q.url) or (q.provider_id is not null and security.provider_sch_search_off_v1(q.provider_id)));
  -- CF-247 15 Oct (waste rules): a queued candidate whose page was stored within the reuse time takes that copy, so it is not read again
  update pipeline.scholarship_page_candidates c set storage_path = x.storage_path, content_hash = x.content_hash, evidence_id = coalesce(c.evidence_id, x.evidence_id)
    from (select distinct on (q.candidate_id) q.candidate_id, e.storage_path, e.content_hash, e.evidence_id
            from pipeline.scholarship_ai_queue q
            join pipeline.scholarship_ai_extractions e on e.url = q.url and e.storage_path is not null and e.error is null and e.at > now() - make_interval(hours => v_reuse)
           where q.state = 'queued' and q.next_try_at <= now() and q.candidate_id is not null
           order by q.candidate_id, e.at desc) x
   where c.id = x.candidate_id and c.storage_path is null and v_reuse > 0;
  with pick as (
    select q.id from pipeline.scholarship_ai_queue q
     where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3
     order by (q.run_kind = 'test') desc, (q.run_kind = 'qualify') desc, q.step desc, q.id
     limit greatest(1, least(coalesce(p_limit, 8), 20)) for update skip locked),
  upd as (update pipeline.scholarship_ai_queue q set state = 'leased', leased_until = now() + interval '4 minutes', attempts = q.attempts + 1 from pick where q.id = pick.id returning q.*)
  select coalesce(jsonb_agg(jsonb_build_object('queue_id', u.id, 'model_code', u.model_code, 'model', m.model_identifier, 'prompt_version', u.prompt_version,
           'prompt', (select p.text from pipeline.scholarship_ai_prompts p where p.version = u.prompt_version), 'run_kind', u.run_kind, 'url', u.url,
           'candidate_id', u.candidate_id, 'scholarship_id', u.scholarship_id, 'provider_id', u.provider_id, 'country', case when u.provider_id is not null then security.coverage_country(u.provider_id) end,  -- v2.15.256
           'provider', (select coalesce(pr.display_name, pr.canonical_name) from catalogue.providers pr where pr.id = u.provider_id),
           'currency', case when u.provider_id is not null then scholarship.provider_currency(u.provider_id) else 'AUD' end,
           'storage_path', coalesce(u.storage_path, (select c.storage_path from pipeline.scholarship_page_candidates c where c.id = u.candidate_id),
                                    (select e.storage_path from pipeline.scholarship_pages sp join pipeline.evidence_artifacts e on e.id = sp.evidence_id where sp.scholarship_id = u.scholarship_id),
                                    (select e.storage_path from scholarship.scholarships s join pipeline.evidence_artifacts e on e.id = s.evidence_id where s.id = u.scholarship_id),
                                    -- CF-247 15 Oct (waste rules): a copy of the same page stored within the reuse time
                                    (select x.storage_path from pipeline.scholarship_ai_extractions x where x.url = u.url and x.storage_path is not null and x.error is null and x.at > now() - make_interval(hours => v_reuse) order by x.at desc limit 1)))), '[]'::jsonb)
    into v from upd u join pipeline.scholarship_ai_models m on m.code = u.model_code;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION security.platform_notices_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w_or int := coalesce((security.toolset_setting('openrouter', 'notice_window_hours'))::text::int, 24);
  w_job int := coalesce((security.toolset_setting('scheduled_jobs', 'notice_window_hours'))::text::int, 24);
  w_edge int := coalesce((security.toolset_setting('edge_functions', 'notice_window_hours'))::text::int, 6);
  v_or_mode text := coalesce((select t.enforcement from pipeline.platform_toolsets t where t.key = 'openrouter'), 'stop');
  v jsonb := '[]'::jsonb;
begin
  -- v2.15.258 (bug 12/10-01): OpenRouter notices for the AI uses that run now (Layer 3 retired on 12 Oct 2026). Refused calls
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'openrouter:2:refused:' || z.code, 'layer', 2, 'toolset', 'openrouter', 'kind', 'refused', 'severity', 'high',
      'title', case z.code when 'credit' then 'OpenRouter refused calls: out of credit'
                           when 'key_limit' then 'OpenRouter refused calls: the key''s own spending limit was reached'
                           when 'rate' then 'OpenRouter refused calls: rate limit'
                           else 'OpenRouter refused calls: key not accepted' end,
      'detail', format('%s AI calls in the last %s hours were refused; those pages are read again later.', z.n, w_or),
      'hint', case z.code when 'credit' then 'Top up the OpenRouter balance; the refused pages are read again by themselves.'
                          when 'key_limit' then 'The limit is set on the key at OpenRouter (Workspaces › Keys), not in StudySearch. Raise or clear it there.'
                          when 'rate' then 'Usually clears by itself; the pages are read again.'
                          else 'Check the OpenRouter key on Settings.' end,
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    from (select case when r.e ilike '%key limit%' or r.e ilike '%weekly limit%' then 'key_limit' when r.e ~ 'HTTP 402' or r.e ilike '%credit%' then 'credit'
                      when r.e ~ 'HTTP 429' then 'rate' else 'key' end code, count(*) n, min(r.at) first_at, max(r.at) last_at
          from (select x.error e, x.at from pipeline.scholarship_ai_extractions x where x.at > now() - make_interval(hours => w_or) and x.error ~ 'HTTP (40[123]|429)'
                union all
                select q.error, coalesce(q.done_at, q.created_at) from pipeline.central_ai_queue q where q.created_at > now() - make_interval(hours => w_or) and q.error ~ 'HTTP (40[123]|429)') r
          group by 1) z), '[]'::jsonb);

  -- OpenRouter balance: below the warning level, below the credit floor, or not read recently (read by the openrouter-balance job)
  v := v || coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('key', 'openrouter:2:low_balance', 'layer', 2, 'toolset', 'openrouter', 'kind', 'low_balance',
      'severity', case when o.remaining_usd < coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0) then 'high' else 'warning' end,
      'title', format('OpenRouter balance is US$%s', round(o.remaining_usd, 2)),
      'detail', case when o.remaining_usd < coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0)
                     then format('Below the credit floor of US$%s. AI is set to %s.', security.toolset_setting('openrouter', 'credit_floor_usd'),
                                 case v_or_mode when 'observe' then 'observe only, so it keeps running until OpenRouter refuses calls' else 'stop at limits, so the scholarship AI and central pages AI have stopped' end)
                     else format('Below the warning level of US$%s. AI is set to %s.', security.toolset_setting('openrouter', 'low_balance_warn_usd'),
                                 case v_or_mode when 'observe' then 'observe only' else 'stop at limits' end) end,
      'hint', 'Top up the OpenRouter account the platform''s key uses.',
      'count', 1, 'first_at', o.observed_at, 'last_at', o.observed_at) x
    from (select * from pipeline.layer3_openrouter_observations where kind = 'credits' order by observed_at desc limit 1) o
    where o.remaining_usd < greatest(coalesce((security.toolset_setting('openrouter', 'low_balance_warn_usd'))::text::numeric, 0),
                                     coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0))
    union all
    select jsonb_build_object('key', 'openrouter:2:not_observed', 'layer', 2, 'toolset', 'openrouter', 'kind', 'not_observed', 'severity', 'warning',
      'title', 'OpenRouter balance has not been read recently',
      'detail', format('Last reading %s.', coalesce(to_char(o.observed_at at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI'), 'never')),
      'hint', 'The balance is read every 15 minutes by the scheduled job "Read the OpenRouter balance" (openrouter-balance); check it in Scheduled jobs.',
      'count', 1, 'first_at', o.observed_at, 'last_at', now())
    from (select max(observed_at) observed_at from pipeline.layer3_openrouter_observations where kind = 'credits') o
    where o.observed_at is null or o.observed_at < now() - make_interval(mins => coalesce((security.toolset_setting('openrouter', 'balance_stale_minutes'))::text::int, 30))
  ) q), '[]'::jsonb);

  -- An AI use past its daily guard today (UTC day)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'openrouter:2:over_guard:' || g.use || ':' || to_char(now() at time zone 'UTC', 'YYYY-MM-DD'), 'layer', 2, 'toolset', 'openrouter', 'kind', 'over_guard',
      'severity', case v_or_mode when 'observe' then 'info' else 'warning' end,
      'title', format('%s spent US$%s today, past its guard of US$%s', g.label, g.spent, g.guard),
      'detail', case v_or_mode when 'observe' then 'Observe only: it keeps running. This is recorded for the top-up review.'
                     else 'Stop at limits: it has stopped until the UTC day changes (adapter proposals stop at their own allowance; course-page matching is observed only).' end,
      'hint', 'Change the guard or the mode on Models & services › OpenRouter (AI models) › Daily guards.',
      'count', 1, 'first_at', now(), 'last_at', now()))
    from security.ai_spend_today_v1() g where g.guard > 0 and g.spent >= g.guard), '[]'::jsonb);

  -- Firecrawl balance, scholarship share, course-link search cap (Layer 2)
  v := v || coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('key', 'firecrawl:2:low_balance', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'low_balance', 'severity', 'warning',
      'title', format('Firecrawl has %s credits left this month', o.remaining_units),
      'detail', format('Below the warning level of %s. The period ends %s.', security.toolset_setting('firecrawl', 'low_balance_warn_units'), to_char(o.period_end at time zone 'Australia/Melbourne', 'DD Mon YYYY')),
      'hint', 'Work that needs Firecrawl stops at the reserve set on Scrapers & fetchers.', 'count', 1, 'first_at', o.observed_at, 'last_at', o.observed_at) x
    from (select v2.* from pipeline.vendor_credit_observations v2 join pipeline.layer2_acquisition_providers p on p.id = v2.provider_id and p.provider_key = 'firecrawl' order by v2.observed_at desc limit 1) o
    where o.remaining_units < coalesce((security.toolset_setting('firecrawl', 'low_balance_warn_units'))::text::numeric, 0)
    union all
    -- v2.15.262: the day's Firecrawl budget (a share, or the billed total) at 80% or more
    select jsonb_build_object('key', 'firecrawl:2:daily:' || b.grp || ':' || to_char(now() at time zone 'Australia/Melbourne', 'YYYY-MM-DD'), 'layer', 2, 'toolset', 'firecrawl', 'kind', 'daily_budget',
      'severity', case when b.used >= b.cap then 'high' else 'warning' end,
      'title', format('Firecrawl daily budget, %s: %s of %s credits used', b.label, round(b.used), round(b.cap)),
      'detail', case when b.used >= b.cap then 'Used up: this work waits until midnight, Melbourne time.' else 'At 80% or more; this work stops for the day when it is used up.' end,
      'hint', 'Raise the share under Daily budget if this work should carry on today.', 'count', 1, 'first_at', now(), 'last_at', now())
    from (select 'total' grp, 'billed today' label, (st->>'billed_today')::numeric used, (st->>'total')::numeric cap, (st->>'on')::boolean is_on from security.fc_budget_status_v1() st
          union all
          select g->>'group', g->>'label', (g->>'used')::numeric, (g->>'share')::numeric, (st->>'on')::boolean
            from security.fc_budget_status_v1() st, jsonb_array_elements(st->'groups') g) b
    where b.is_on and b.cap > 0 and b.used >= 0.8 * b.cap
    union all
    select jsonb_build_object('key', 'firecrawl:2:search_stopped', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'search_stopped', 'severity', 'warning',
      'title', format('Course-page search stopped for %s universit%s', s.n, case when s.n = 1 then 'y' else 'ies' end),
      'detail', format('No correct course page after %s searches. Usually the website on record is wrong or the site hides its course pages from search.', security.fc_setting_num_v1('search_stop_after', 30)),
      'hint', 'Check the website on record (correct it on the provider if it is wrong), then press Search again.', 'count', s.n, 'first_at', now(), 'last_at', now(), 'items', s.items)
    from (select count(*) n, jsonb_agg(jsonb_build_object('provider_id', f.provider_id, 'name', coalesce(p.display_name, p.canonical_name), 'website', p.website,
                                                          'searches', f.searches) order by f.searches desc, p.canonical_name) items
            from security.fc_search_stopped_v1() f join catalogue.providers p on p.id = f.provider_id
           where f.searches > 0
             and not exists (select 1 from pipeline.firecrawl_search_holds h where h.provider_id = f.provider_id
                               and not exists (select 1 from pipeline.firecrawl_search_resumes r where r.provider_id = h.provider_id and r.resumed_at > h.held_at))) s where s.n > 0
    union all
    -- v2.15.265: course search held for an adapter check, by name
    select jsonb_build_object('key', 'firecrawl:2:search_held', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'search_held', 'severity', 'warning',
      'title', format('Course-page search held for %s: %s', count(*), string_agg(coalesce(p.display_name, p.canonical_name), ', ' order by p.canonical_name)),
      'detail', string_agg(coalesce(p.display_name, p.canonical_name) || ': ' || h.reason, '; ' order by p.canonical_name),
      'hint', 'Check the university''s adapter and website, then press Search again.', 'count', count(*), 'first_at', min(h.held_at), 'last_at', now(),
      'items', jsonb_agg(jsonb_build_object('provider_id', h.provider_id, 'name', coalesce(p.display_name, p.canonical_name), 'website', p.website, 'reason', h.reason) order by p.canonical_name))
    from pipeline.firecrawl_search_holds h join catalogue.providers p on p.id = h.provider_id
   where not exists (select 1 from pipeline.firecrawl_search_resumes r where r.provider_id = h.provider_id and r.resumed_at > h.held_at)
  having count(*) > 0
    union all
    -- v2.15.265: Australian providers whose official website was searched for and not found
    select jsonb_build_object('key', 'firecrawl:2:no_official_site', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'no_official_site', 'severity', 'info',
      'title', format('%s Australian providers have no official website found', count(*)),
      'detail', 'Not in the CRICOS register, TEQSA or training.gov.au, and no site showing their CRICOS code. Course pages and scholarships are not searched for them.',
      'hint', 'Enter a website if you know it: the course-page search starts within minutes. Otherwise nothing to do.', 'count', count(*), 'first_at', min(d.site_searched_at), 'last_at', max(d.site_searched_at),
      'items', jsonb_agg(jsonb_build_object('provider_id', d.provider_id, 'name', coalesce(p.display_name, p.canonical_name)) order by p.canonical_name))
    from pipeline.coverage_provider_discovery d join catalogue.providers p on p.id = d.provider_id and p.lifecycle_status = 'active'
   where d.status = 'no_website' and d.site_searched_at is not null and nullif(btrim(p.website), '') is null and security.coverage_country(d.provider_id) = 'AU'
  having count(*) > 0
    union all
    -- v2.15.265: providers sharing one website (pathway colleges on their university's site): their searches read the other's pages
    select jsonb_build_object('key', 'firecrawl:2:shared_site', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'shared_site', 'severity', 'info',
      'title', format('%s providers share a website with another provider', sum(z.n)),
      'detail', 'Examples: ' || string_agg(z.host, ', ' order by z.n desc) filter (where z.rk <= 5),
      'hint', 'Usually a pathway college on its university''s site. Give the college its own website, or leave it: scholarships are not searched for providers with fewer than 30 courses.', 'count', sum(z.n), 'first_at', now(), 'last_at', now())
    from (select y.host, y.n, row_number() over (order by y.n desc, y.host) rk from (
            select security.fc_spend_host_v1(p.website) host, count(*) n from catalogue.providers p
             where p.lifecycle_status = 'active' and p.website ~* '^https?://' group by 1 having count(*) > 1) y where y.host is not null) z
  having count(*) > 0
    union all
    select jsonb_build_object('key', 'firecrawl:2:scholarship_share', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'cap_reached', 'severity', 'warning',
      'title', format('Scholarship Firecrawl share: %s of %s credits used', s.used, s.cap),
      'detail', format('Fewer than the reserve of %s are left, so newly found scholarship pages that refuse a direct read are not read.', s.reserve),
      'hint', 'Raise the cap on Layer 2 › Scholarships if you want them read.', 'count', 1, 'first_at', now(), 'last_at', now())
    from (select (b->>'used')::numeric used, (b->>'cap')::numeric cap, (b->>'reserve')::numeric reserve
          from (select jsonb_build_object(
                  'used', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose in ('sch_map', 'sch_search', 'sch_scrape')),
                  'cap', (select s2.value from pipeline.scholarship_layer_settings s2 where s2.key = 'firecrawl_cap'),
                  'reserve', (select s2.value from pipeline.scholarship_layer_settings s2 where s2.key = 'firecrawl_reserve')) b) q) s
    where s.cap - s.used <= s.reserve
    union all
    select jsonb_build_object('key', 'firecrawl:2:course_link_cap:' || to_char(now(), 'YYYY-MM'), 'layer', 2, 'toolset', 'firecrawl', 'kind', 'cap_reached', 'severity', 'warning',
      'title', format('Course-link search used %s of its %s monthly credits', l.used, l.cap),
      'detail', 'Course-link search stops for the rest of the month.', 'hint', 'Change the monthly cap on Jobs › Priority.',
      'count', 1, 'first_at', now(), 'last_at', now())
    from (select (select monthly_credit_cap from pipeline.course_link_search_settings limit 1) cap,
                 (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose = 'course_link_search' and u.at >= date_trunc('month', now())) used) l
    where l.used >= l.cap
  ) q), '[]'::jsonb);

  -- Scheduled jobs that timed out or failed (the job's layer)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'scheduled_jobs:' || z.layer || ':' || z.kind || ':' || z.jobname, 'layer', z.layer, 'toolset', 'scheduled_jobs', 'kind', z.kind,
      'severity', case when z.n >= 5 then 'high' else 'warning' end,
      'title', case z.kind when 'timeout' then format('Job "%s" hit the database time limit %s times', z.jobname, z.n)
                           else format('Job "%s" failed %s times', z.jobname, z.n) end,
      'detail', format('In the last %s hours (%s runs in all). Last message: %s', w_job, z.runs, z.msg),
      'hint', case z.kind when 'timeout' then 'Lower the job''s batch size setting so each run finishes inside the limit.' else 'Usually clears by itself (for example a deadlock); if it repeats, the job needs a fix.' end,
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    -- (11 Oct 2026: the run history is read once, last 7 days; only the jobs that failed are ranked for "last three runs succeeded")
    from (with hist as materialized (select h.jobid, h.status, h.return_message, h.start_time, h.end_time
                                       from cron.job_run_details h where h.start_time > now() - interval '7 days'), -- fixed: run history read once, last 7 days
               fd as materialized (select * from hist where status = 'failed' and end_time > now() - make_interval(hours => w_job)),
               fj as materialized (select distinct jobid from fd),
               last3 as (select f.jobid, bool_and(t.status = 'succeeded') ok, count(*) c from fj f
                           cross join lateral (select x.status from hist x where x.jobid = f.jobid and x.status in ('succeeded', 'failed')
                                               order by x.start_time desc limit 3) t group by f.jobid),
               runs as (select x.jobid, count(*) n from hist x where x.jobid in (select jobid from fj)
                          and x.end_time > now() - make_interval(hours => w_job) group by x.jobid)
          select j.jobname, coalesce(l.layer, 2) layer,
                 case when d.return_message ilike '%statement timeout%' then 'timeout' else 'failed' end kind,
                 count(*) n, min(d.end_time) first_at, max(d.end_time) last_at, left(max(d.return_message), 140) msg,
                 max(coalesce(rn.n, 0)) runs
          from fd d join cron.job j on j.jobid = d.jobid left join pipeline.platform_job_layers l on l.jobname = j.jobname
          left join last3 l3 on l3.jobid = d.jobid left join runs rn on rn.jobid = d.jobid
          where not (coalesce(l3.ok, false) and coalesce(l3.c, 0) = 3)
          group by j.jobid, j.jobname, l.layer, 3
          having count(*) >= coalesce((security.toolset_setting('scheduled_jobs', 'min_failures'))::text::int, 1)) z), '[]'::jsonb);

  -- Edge function calls that timed out (platform)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'edge_functions:0:timeout', 'layer', 0, 'toolset', 'edge_functions', 'kind', 'timeout', 'severity', 'warning',
      'title', format('%s edge function calls timed out or hit the worker limit', z.n),
      'detail', format('In the last %s hours.', w_edge), 'hint', 'The worker runs too long per call; lower its per-run limit.',
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    from (select count(*) n, min(r.created) first_at, max(r.created) last_at from net._http_response r
          where r.created > now() - make_interval(hours => w_edge) and (r.timed_out or r.status_code in (504, 546))) z
    where z.n >= coalesce((security.toolset_setting('edge_functions', 'min_timeouts'))::text::int, 1)), '[]'::jsonb);

  -- v2.15.269: a running job with a number written into it (it should read a setting)
  v := v || coalesce((select jsonb_agg(jsonb_build_object('key', 'pipeline:0:fixed_value:' || c.jobname, 'layer', 0, 'toolset', 'pipeline', 'kind', 'fixed_value', 'severity', 'warning',
      'title', format('Job "%s" has a number written into it', c.jobname),
      'detail', 'Its size or limit should come from Pipeline settings, so it can be changed on screen.',
      'hint', 'Move the value to the settings register (Pipeline settings).', 'count', 1, 'first_at', now(), 'last_at', now()))
    from security.controls_check_v1() c), '[]'::jsonb);

  -- CF-247 15 Oct 2026 (waste rules): jobs paused for producing nothing, and values frozen after automatic writers disagreed
  v := v || coalesce((select jsonb_agg(jsonb_build_object('key', 'pipeline:0:waste_paused:' || w.jobname, 'layer', 0, 'toolset', 'pipeline', 'kind', 'waste_paused', 'severity', 'warning',
      'title', format('Job "%s" paused: it produced nothing', w.jobname),
      'detail', format('Paused %s: no output and nothing waiting for it. It resumes by itself when work arrives.', to_char(w.paused_at at time zone 'Australia/Melbourne', 'DD Mon HH24:MI')),
      'hint', 'Nothing to do. The time is on Pipeline settings › Waste rules.', 'count', 1, 'first_at', w.paused_at, 'last_at', w.paused_at))
    from pipeline.job_idle_watch w where w.paused_at is not null), '[]'::jsonb);
  v := v || coalesce((select jsonb_agg(jsonb_build_object('key', 'pipeline:0:waste_frozen', 'layer', 0, 'toolset', 'pipeline', 'kind', 'waste_frozen', 'severity', 'warning',
      'title', format('%s course values frozen: automatic writers kept changing them', z.n),
      'detail', 'Each changed more often than Pipeline settings › Waste rules allows; it is kept as it is and left out of automatic updates.',
      'hint', 'Check them and set the right value by hand.', 'count', z.n, 'first_at', z.f, 'last_at', z.l))
    from (select count(*) n, min(f.flagged_at) f, max(f.flagged_at) l from pipeline.enrichment_flags f where f.reason_code = 'flip_flop' and f.cleared_at is null) z where z.n > 0), '[]'::jsonb);

  return v;
end $function$;

-- 5 Jobs
-- The admit jobs run on new input (and a full check every few hours); the commands keep their settings
select cron.alter_job((select jobid from cron.job where jobname = 'coverage-admit'),
  command := 'select security.coverage_admission_gated_v1(''coverage-admit'', security.pipeline_num_v1(''batch.coverage_admit'', 500)::int, ''coverage-sweep-v0.5.6'', array[''official_url'', ''english''])');
select cron.alter_job((select jobid from cron.job where jobname = 'coverage-admit-intakes'),
  command := 'select security.coverage_admission_gated_v1(''coverage-admit-intakes'', security.pipeline_num_v1(''batch.coverage_admit_intakes'', 300)::int, ''coverage-sweep-v0.5.6'', array[''intakes''])');
select cron.alter_job((select jobid from cron.job where jobname = 'adapter-overwrite'),
  command := 'select security.adapter_overwrite_gated_v1(security.pipeline_num_v1(''batch.adapter_overwrite'', 200)::int)');
update pipeline.automation_catalogue set description = coalesce(description, '') || ' Runs only when new input has arrived, with a full check every few hours (Waste rules, 15 Oct 2026).'
 where jobname in ('coverage-admit', 'coverage-admit-intakes', 'adapter-overwrite') and coalesce(description, '') not like '%Waste rules%';

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('waste-guard', 'Platform upkeep', 91, 'Waste rules: pause idle jobs, freeze flip-flops, flag',
  'Hourly: pauses a watched job that produced nothing with nothing waiting (and switches it on again when work arrives), freezes course values two automatic writers keep changing, and records what was stopped and why (pipeline.enrichment_flags).', 6, false),
 ('enrich-focus-refresh', 'Course pages', 73, 'Focus providers for course-page search',
  'Weekly: ranks Australian providers by missing English and intakes; course-page search runs only for the top ones (Pipeline settings › Waste rules).', 6, false)
on conflict do nothing;
select cron.schedule('waste-guard', '17 * * * *', 'select security.waste_guard_v1()');
select cron.schedule('enrich-focus-refresh', '41 17 * * 0', 'select security.enrich_focus_refresh_v1()');

-- 6 First run
insert into pipeline.job_input_marks(job_key) values ('flipflop-guard') on conflict do nothing;  -- changes before now are not counted
insert into pipeline.job_idle_watch(jobname, output_sql, input_sql, note) values
 ('course-link-reverse',
  'select count(*) from pipeline.course_link_reverse where done_at > $1',
  'select count(*) from pipeline.course_link_reverse where state in (''queued'', ''sent'')',
  'Matches course pages by the CRICOS codes printed on them; it last read a page on 30 Sep 2026 and has bound 2 courses.')
on conflict do nothing;
select security.enrich_focus_refresh_v1();
select security.waste_guard_v1();

do $post$
declare v_expected jsonb := '{"security.coverage_admission_apply_v1(integer,text,text[])": "9667b916c5a9bfce01409b1668b2558c", "security.coverage_ai_match_prepare_v1(integer,integer)": "01ad8260df8442e29df2bbfd07af8385", "public.svc_course_link_search_next(integer)": "8b6c6f829d6269a0448ed9e6faff5aa0", "public.svc_coverage_discovery_next(integer)": "d7a00f4928be0f4ea8b610013e219cc0", "security.exit_awards_apply_v2(uuid)": "8d4e5f7b2fedbe7c3e04ff8b039c40e7", "security.firecrawl_panel_refresh_v1()": "098c8d6df542454266a4a3e17cd10db9", "public.svc_scholarship_ai_next(integer)": "11de2cc8382b69ed2dfb9d4e92209771", "security.platform_notices_v1()": "7580ed3340d12b38d379254906a09d8e"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'waste rules post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;

do $post2$
declare v_n int;
begin
  select count(*) into v_n from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and section = 'Waste rules';
  if v_n <> 10 then raise exception 'waste rules post-check: % settings, expected 10', v_n; end if;
  select count(*) into v_n from cron.job where jobname in ('waste-guard', 'enrich-focus-refresh') and active;
  if v_n <> 2 then raise exception 'waste rules post-check: % of 2 new jobs scheduled', v_n; end if;
  select count(*) into v_n from cron.job where jobname in ('coverage-admit', 'coverage-admit-intakes', 'adapter-overwrite') and command ~ '_gated_v1\(';
  if v_n <> 3 then raise exception 'waste rules post-check: % of 3 admit jobs input-driven', v_n; end if;
  select count(*) into v_n from pipeline.enrich_focus_providers where in_focus;
  if v_n <> security.pipeline_num_v1('enrich.focus_top_n', 50)::int then raise exception 'waste rules post-check: % focus providers', v_n; end if;
  if exists (select 1 from security.controls_check_v1()) then raise exception 'waste rules post-check: a running job has a number written into it'; end if;
end $post2$;
