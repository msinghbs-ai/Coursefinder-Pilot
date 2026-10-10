-- CF-247, 8 Oct 2026 (Platform Admin: bring down the database and storage size; purging from the screen, Platform Admin only).
-- Part 1 of 3: run log, estimates and the screen's function (read, preview, purge, stop). Nothing is deleted by this part.
-- Categories and rules (approved 8 Oct 2026):
--   adapter_screenshots : adapter builder screenshots older than 7 days (the stored HTML and text blocks that proposals use are kept)
--   retired_layer2      : the Layer 2 tables retired on 2 Oct (scope wave items, scale qualification items, provider attempts, course discovery
--                         candidates, provider trial results). Run items stay: Layer 3 work items still point to them.
--   job_log             : scheduled-job run log older than 7 days
--   directory_urls      : sitemap URLs on third-party course directories shared by 3 or more providers, for providers whose own website is
--                         another site; URLs bound to a course are kept (they are in Layer 4 review)
--   evidence_audit      : count only. Evidence files not referenced by any value, decision or record; nothing is deleted
-- Purging runs as a background job in small batches (part 2) and every run is logged here.
create table if not exists pipeline.retention_runs (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('adapter_screenshots', 'retired_layer2', 'job_log', 'directory_urls', 'evidence_audit')),
  status text not null default 'queued' check (status in ('queued', 'running', 'done', 'failed', 'stopped')),
  removed bigint not null default 0, bytes bigint not null default 0, note text, error text,
  estimate jsonb, requested_by uuid not null, reason text not null,
  created_at timestamptz not null default now(), started_at timestamptz, finished_at timestamptz, updated_at timestamptz not null default now());
create unique index if not exists retention_runs_one_active on pipeline.retention_runs(category) where status in ('queued', 'running');
alter table pipeline.retention_runs enable row level security;
revoke all on pipeline.retention_runs from public, anon, authenticated;

create table if not exists pipeline.retention_estimates (
  category text primary key, size_bytes bigint, purgeable_rows bigint, purgeable_bytes bigint, detail jsonb, measured_at timestamptz not null default now());
alter table pipeline.retention_estimates enable row level security;
revoke all on pipeline.retention_estimates from public, anon, authenticated;

create table if not exists pipeline.evidence_audit_refs (evidence_id uuid primary key);
create table if not exists pipeline.evidence_audit_columns (tbl text not null, col text not null, done_at timestamptz, rows_found bigint, primary key (tbl, col));
alter table pipeline.evidence_audit_refs enable row level security;
alter table pipeline.evidence_audit_columns enable row level security;
revoke all on pipeline.evidence_audit_refs, pipeline.evidence_audit_columns from public, anon, authenticated;

create or replace function security.retention_catalogue_v1()
returns jsonb language sql stable set search_path to '' as $f$
  select jsonb_build_array(
    jsonb_build_object('key', 'adapter_screenshots', 'label', 'Adapter builder screenshots', 'kind', 'files', 'purge', true,
      'rule', 'Screenshots captured by the adapter builder more than 7 days ago. The stored page HTML and text blocks that proposals use are kept; the builder shows "screenshot removed".'),
    jsonb_build_object('key', 'retired_layer2', 'label', 'Retired Layer 2 tables', 'kind', 'rows', 'purge', true,
      'rule', 'Rows of the Layer 2 tables retired on 2 Oct 2026: scope wave items, scale qualification items, provider attempts, course discovery candidates and provider trial results. Run items are kept because Layer 3 work items point to them.'),
    jsonb_build_object('key', 'job_log', 'label', 'Scheduled-job run log', 'kind', 'rows', 'purge', true,
      'rule', 'Run records of scheduled jobs older than 7 days. Platform health and the job notices only use the last 24 hours.'),
    jsonb_build_object('key', 'directory_urls', 'label', 'Course-directory sitemap copies', 'kind', 'rows', 'purge', true,
      'rule', 'Sitemap addresses on third-party course directories shared by 3 or more providers, kept for providers whose own website is a different site. Addresses bound to a course are kept (they are in Layer 4 review).'),
    jsonb_build_object('key', 'evidence_audit', 'label', 'Evidence files (audit)', 'kind', 'files', 'purge', false,
      'rule', 'Count only: evidence records and files not referenced by any value, decision or pipeline record. Nothing is deleted; a purge rule needs a separate decision.'))
$f$;

create or replace function public.admin_retention(p_action text, p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_rank int := security.current_role_rank(); v_cat text := btrim(coalesce(p_args->>'category', '')); v_reason text := btrim(coalesce(p_args->>'reason', ''));
        v_c jsonb; v_id uuid; v_e jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if p_action = 'read' then
    return jsonb_build_object(
      'database_bytes', pg_database_size(current_database()),
      'categories', (select jsonb_agg(c || jsonb_build_object(
          'estimate', (select to_jsonb(e) - 'category' from pipeline.retention_estimates e where e.category = c->>'key'),
          'active', (select to_jsonb(r) from pipeline.retention_runs r where r.category = c->>'key' and r.status in ('queued', 'running') limit 1),
          'last', (select to_jsonb(r) from pipeline.retention_runs r where r.category = c->>'key' and r.status not in ('queued', 'running') order by r.created_at desc limit 1)))
        from jsonb_array_elements(security.retention_catalogue_v1()) c),
      'runs', coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from (select * from pipeline.retention_runs order by created_at desc limit 15) r), '[]'::jsonb));
  end if;
  select c into v_c from jsonb_array_elements(security.retention_catalogue_v1()) c where c->>'key' = v_cat;
  if v_c is null then raise exception 'unknown category'; end if;
  if p_action = 'preview' then
    select to_jsonb(e) into v_e from pipeline.retention_estimates e where e.category = v_cat;
    return jsonb_build_object('category', v_c, 'estimate', v_e, 'note', 'Counts are measured in the background (hourly) and at the start of each purge; nothing is changed by a preview.');
  end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'purge' then
    if not (v_c->>'purge')::boolean and v_cat <> 'evidence_audit' then raise exception 'this category cannot be purged'; end if;
    if v_cat <> 'evidence_audit' and coalesce(p_args->>'confirm', '') <> v_cat then raise exception 'type the category name (%) to confirm', v_cat; end if;
    if exists (select 1 from pipeline.retention_runs r where r.category = v_cat and r.status in ('queued', 'running')) then raise exception 'a run for this category is already in progress'; end if;
    insert into pipeline.retention_runs(category, requested_by, reason, estimate, note)
    values (v_cat, auth.uid(), v_reason, (select to_jsonb(e) from pipeline.retention_estimates e where e.category = v_cat),
            case when v_cat = 'evidence_audit' then 'Audit queued: counts references in the background; nothing is deleted.' else 'Queued: starts within 2 minutes and runs in small batches.' end)
    returning id into v_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('retention', case when v_cat = 'evidence_audit' then 'retention_audit' else 'retention_purge' end, v_cat, jsonb_build_object('run_id', v_id, 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'run_id', v_id);
  elsif p_action = 'stop' then
    update pipeline.retention_runs set status = 'stopped', note = 'Stopped by a Platform Admin: ' || v_reason, finished_at = now(), updated_at = now()
     where category = v_cat and status in ('queued', 'running') returning id into v_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('retention', 'retention_stop', v_cat, jsonb_build_object('run_id', v_id, 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', v_id is not null);
  end if;
  raise exception 'unknown action';
end $f$;
revoke all on function public.admin_retention(text, jsonb) from public, anon;
grant execute on function public.admin_retention(text, jsonb) to authenticated, service_role;
revoke all on function security.retention_catalogue_v1() from public, anon, authenticated;
