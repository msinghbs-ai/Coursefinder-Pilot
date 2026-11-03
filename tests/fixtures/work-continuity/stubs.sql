-- CF-247 SS-021 work continuity (migration 20261104170000) on isolated fixtures: the live shapes this change reads or calls beyond
-- ../integration-queue/stubs.sql, the integration queue (20261102120000), ../ops-controller/stubs-extra.sql and workstream A's migrations, which
-- run.sh loads first. Columns read from information_schema on production (read-only, 3 Nov 2026 21:24-21:29 AEDT). Run on a scratch PostgreSQL
-- only (never on a Supabase project): see run.sh. Nothing here is live data.

-- field items (live columns used here)
alter table pipeline.field_enrich_items add column if not exists attempts int not null default 0, add column if not exists job_id uuid;

-- Layer 4 status (live check)
alter table pipeline.layer4_review_items add constraint layer4_review_items_status_check
  check (status = any (array['pending', 'approved', 'edited_approved', 'rejected', 'more_evidence', 'returned_layer2', 'returned_layer3', 'superseded']));

-- course re-linking (live columns)
create table pipeline.coverage_course_pages(course_id uuid primary key, provider_id uuid not null, read_status text, status text, url text, identity_basis text,
  leased_until timestamptz, read_attempts int, next_read_at timestamptz);
create table pipeline.course_relink(course_id uuid primary key, provider_id uuid, old_url text, candidates jsonb, sources jsonb, pattern text, state text, reason text,
  result_url text, rule int, started_at timestamptz default now(), decided_at timestamptz);
create table pipeline.course_link_search(course_id uuid primary key, provider_id uuid, stage text, state text, candidates jsonb, cand_idx int, bound_url text,
  queued_at timestamptz, done_at timestamptz, requested_at timestamptz, results jsonb, attempts int);
create function security.course_relink_statuses_v1() returns text[] language sql stable as $f$ select array['identity_mismatch', 'not_found'] $f$;
create function security.source_proof_relink_asked_v1(p_course uuid, p_at timestamptz) returns boolean language sql stable as $f$ select false $f$;
create function security.page_refind_settle_v1() returns void language sql as $f$ select $f$;
create table fx.hidden(provider_id uuid primary key);
create view security.provider_hidden_v1 as select provider_id from fx.hidden;

-- the university re-link step: a stand-in with the live interface (returns {trying, absent}); fx.relink_mode says what each university does
create table fx.relink_mode(provider_id uuid primary key, mode text not null default 'ok', sleep_s numeric not null default 0);
create table fx.relink_calls(id bigserial primary key, provider_id uuid, at timestamptz default clock_timestamp());
create function security.course_relink_provider_v1(p_provider_id uuid, p_limit integer) returns jsonb language plpgsql as $f$
declare v_mode text; v_sleep numeric; v_n int;
begin
  insert into fx.relink_calls(provider_id) values (p_provider_id);
  select mode, sleep_s into v_mode, v_sleep from fx.relink_mode where provider_id = p_provider_id;
  if coalesce(v_sleep, 0) > 0 then perform pg_sleep(v_sleep); end if;
  if v_mode = 'error' then raise exception 'relink of % failed: could not parse address forms', p_provider_id; end if;
  insert into pipeline.course_relink(course_id, provider_id, state, rule)
  select p.course_id, p.provider_id, 'trying', 2 from pipeline.coverage_course_pages p where p.provider_id = p_provider_id
     and p.read_status = any (security.course_relink_statuses_v1()) order by p.course_id limit greatest(1, p_limit)
  on conflict (course_id) do nothing;
  get diagnostics v_n = row_count;
  return jsonb_build_object('forms', 0, 'trying', v_n, 'absent', 0);
end $f$;

-- the paid-lane budget check's helpers (live names; fx.budget says whether a purpose has room)
create table fx.budget(purpose text primary key, left_credits numeric not null);
create function security.fc_month_refusal_v1(p_units numeric) returns text language sql stable as $f$ select null::text $f$;
create function security.fc_budget_left_v1(p_purpose text) returns numeric language sql stable as $f$ select coalesce((select left_credits from fx.budget where purpose = p_purpose), 100) $f$;
create function security.fc_purpose_group_v1(p_purpose text) returns text language sql stable as $f$ select p_purpose $f$;

-- the existing review-category caps (live settings; values for the fixture)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, min_value, max_value, unit, used_by) values
 ('pipeline', 'aer.schedule_layer4_max', 'Scheduled entry reading: stop new reads while Layer 4 holds', 'number', to_jsonb(600), 50, 5000, 'items', 'security.aer_schedule_tick_v1'),
 ('pipeline', 'bind.no_page_pending_max', 'No page published: first runs waiting at most', 'number', to_jsonb(60), 5, 500, 'first runs', 'security.no_page_propose_v1'),
 ('pipeline', 'pdesc.pending_max', 'Provider descriptions: waiting in Layer 4 at most', 'number', to_jsonb(10), 1, 500, 'items', 'public.svc_provider_description_next')
on conflict do nothing;

-- the course-relink job (live schedule and command)
insert into cron.job(jobname, schedule, command) values ('course-relink', '4-59/10 * * * *', $c$select security.course_relink_tick_v1(security.pipeline_num_v1('batch.course_relink', 200)::int)$c$);

-- one of the SS-021 audit's live root causes (registered in production by the audit agent, 3 Nov 2026 about 21:50 AEDT)
select security.ops_root_cause_register_v1('wc_head_of_line_fixed_order', '{"class": "rule", "title": "A fixed order puts the same blocked item first every run", "detect": {"priority": 40, "confidence": 0.8, "any": [{"fingerprint_like": ["wc:%"]}]}}'::jsonb);
