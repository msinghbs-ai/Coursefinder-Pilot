-- CF-247 (24 Oct 2026). UI audit Phase 0 — incidents first (Platform Admin 24 Oct 2026 11:27; decision record: admin repo
-- docs/platform/ui-audit/2026-10-24-ui-cleanup-mandate.md; audit: docs/platform/ui-audit/2026-10-24-admin-ui-audit.md).
-- 1 UI error log: the app shows a person one plain line with a short reference and writes the full error here
--   (public.admin_ui_error_report). The Platform Admin finds it by reference: select * from pipeline.ui_error_log where ref = '…'.
-- 2 coverage-admit has failed every run since 23 Oct 11:40 UTC (77 runs in 48 h): Decision 263 "take" rules applied a plain http://
--   course address and security.layer4_course_link_apply_impl refuses anything but https://, which aborted the whole batch —
--   23,928 official-page and 11,249 English plan rows were not admitting. The rule now never applies an http:// address; such a row
--   becomes an ordinary pending Layer 4 item ("please check which page is current"), the same as a row no rule decides.
--   (The raw error reached three screens; the app now shows "A course page address was not a secure (https) web address…".)
-- 3 "Fully complete courses" fell 5,660 → 0 on 20 Oct: three attributes with no reader yet (deadline, academic_entry, description)
--   joined the coverage matrix that day, and a course counted as fully complete only when every attribute — readable or not — was
--   admitted. From the next nightly build, fully complete means every attribute the platform can read is admitted; the headline
--   completeness % still counts the unreadable attributes (that is the real gap the website developer sees). The 20–23 Oct rows stay
--   as written (the matrix of those days is gone) and the screen says why.
-- Replaces: nothing (coverage_admission_apply_v1 and course_completeness_build_v1 edited in place, md5-guarded)
-- Retires: nothing

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- 1 UI error log -------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.ui_error_log (
  id bigint generated always as identity primary key,
  ref text not null,
  at timestamptz not null default now(),
  user_id uuid,
  page text,
  message text not null,
  detail jsonb,
  seen_at timestamptz
);
comment on table pipeline.ui_error_log is 'UI audit Phase 0 (24 Oct 2026): every error the admin app showed a person, keyed by the short reference printed on screen (ref); the plain message shown and the full detail (raw message, code, page, time); 90-day retention (ledger-retention)';
create index if not exists ui_error_log_ref_idx on pipeline.ui_error_log (ref);
create index if not exists ui_error_log_at_idx on pipeline.ui_error_log (at desc);
alter table pipeline.ui_error_log enable row level security;

create or replace function public.admin_ui_error_report(p_ref text, p_page text, p_message text, p_detail jsonb) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  if auth.uid() is null then raise exception 'sign in required' using errcode = '42501'; end if;
  insert into pipeline.ui_error_log(ref, user_id, page, message, detail)
  values (left(coalesce(p_ref, ''), 12), auth.uid(), left(coalesce(p_page, ''), 80), left(coalesce(p_message, ''), 400), coalesce(p_detail, '{}'::jsonb))
  returning id into v_id;
  return v_id;
end $$;
grant execute on function public.admin_ui_error_report(text, text, text, jsonb) to authenticated;
comment on function public.admin_ui_error_report(text, text, text, jsonb) is 'UI audit Phase 0: the app writes the full text of an error it showed as a plain line with a reference';

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'retention.ui_error_log_days', 'App error log: kept for', 'Errors the admin app showed a person (with their reference) older than this are removed by the daily ledger-retention job.', 'number', '90'::jsonb, '30', '365', 'days', 780, 'Platform upkeep', 'job ledger-retention', 'UI audit Phase 0')
on conflict (toolset_key, key) do nothing;

do $g$ begin
  if md5(pg_get_functiondef('security.ledger_retention_v1()'::regprocedure)) <> '7865f9488018c337c288d60d05d777bc' then
    raise exception 'live security.ledger_retention_v1 differs from the R3 definition this change replaces';
  end if;
end $g$;
create or replace function security.ledger_retention_v1() returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare n_ledger int; n_zy int; n_h int; n_ui int;
begin
  delete from pipeline.mode_outcome_ledger where run_at < now() - make_interval(days => security.pipeline_num_v1('retention.mode_outcome_ledger_days', 90)::int);
  get diagnostics n_ledger = row_count;
  delete from pipeline.zero_yield_snapshots where at < now() - make_interval(days => security.pipeline_num_v1('retention.zero_yield_snapshots_days', 90)::int);
  get diagnostics n_zy = row_count;
  delete from pipeline.health_snapshots where at < now() - make_interval(days => security.pipeline_num_v1('retention.health_snapshots_days', 90)::int);
  get diagnostics n_h = row_count;
  delete from pipeline.ui_error_log where at < now() - make_interval(days => security.pipeline_num_v1('retention.ui_error_log_days', 90)::int);
  get diagnostics n_ui = row_count;
  return jsonb_build_object('mode_outcome_ledger', n_ledger, 'zero_yield_snapshots', n_zy, 'health_snapshots', n_h, 'ui_error_log', n_ui);
end $function$;

-- 2 coverage-admit: a rule never applies a plain http:// address --------------------------------------------------------------------------
select pg_temp.edit_n('security.coverage_admission_apply_v1(integer,text,text[])', '642639e240ccbca8444df2816209a86c', array[
  array[$o$    v_rule := case when r.attribute = 'official_url' then security.course_page_rule_v1(r.current->>0, r.proposed->>'course_url') end;$o$,
        $n$    v_rule := case when r.attribute = 'official_url' then security.course_page_rule_v1(r.current->>0, r.proposed->>'course_url') end;
    -- 24 Oct 2026 (UI audit Phase 0): a "take" rule never applies a plain http:// address (the link apply refuses it and the whole
    -- batch failed, every run since 23 Oct 11:40 UTC); the row waits for a person instead, like any row no rule decides
    if v_rule like 'take:%' and coalesce(r.proposed->>'course_url', '') !~* '^https://' then v_rule := null; end if;$n$]], array[1]);

-- 3 fully complete = every readable attribute admitted -----------------------------------------------------------------------------------
select pg_temp.edit_n('security.course_completeness_build_v1()', '3de764fe1f20c99a96e3f867dd176dbd', array[
  array[$o$  select course_id, max(provider_id::text)::uuid, max(tier), count(*),
         count(*) filter (where state='admitted'),$o$,
        $n$  select course_id, max(provider_id::text)::uuid, max(tier), count(*) filter (where state<>'no_reader') /* 24 Oct 2026: attributes the platform can read; fully complete = all of them admitted */,
         count(*) filter (where state='admitted'),$n$]], array[1]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.ui_error_log', 'Layer 2', 'errors the admin app showed, by reference', 'active', '{}', '20261024006000'),
 ('function', 'public.admin_ui_error_report', 'Layer 2', 'the app reports an error it showed', 'active', '{}', '20261024006000')
on conflict (kind, name) do nothing;

select 'UI audit Phase 0: error log, coverage-admit http rows wait for a person, fully complete counts readable attributes' ok;
