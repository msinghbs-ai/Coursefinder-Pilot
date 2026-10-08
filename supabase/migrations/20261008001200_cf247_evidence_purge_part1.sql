-- CF-247, 8 Oct 2026 (Platform Admin, multiple choice "Add evidence purge to the screen"): unreferenced evidence can be purged from
-- Platform settings > Storage & retention. Part 1 of 2 (no rows are removed by this part): file queue, skip log, the new category in the
-- catalogue and its estimate, and the worker handshake for evidence files. Part 2 (pasted in the SQL editor) widens the run category and
-- teaches the background worker to purge.
-- Rule for evidence_unreferenced (all must hold):
--   * not referenced by any of the reference columns found by the last completed evidence audit, re-checked for every batch just before
--     removal (a record found referenced is skipped and logged);
--   * created before that audit started and more than 7 days ago;
--   * retention class is not standard_365 (kept for 365 days by policy) and not source_evidence (ranking publisher source files);
--   * the record is removed only if no foreign key still points to it; the file is removed only when no other evidence record uses it.
create table if not exists pipeline.retention_file_queue (
  id bigserial primary key, run_id uuid not null references pipeline.retention_runs(id), bucket text not null, name text not null,
  size bigint not null default 0, status text not null default 'queued' check (status in ('queued', 'handed', 'removed')),
  created_at timestamptz not null default now(), handed_at timestamptz);
create index if not exists retention_file_queue_run_idx on pipeline.retention_file_queue(run_id, status, id);
create table if not exists pipeline.retention_evidence_skips (
  run_id uuid not null references pipeline.retention_runs(id), evidence_id uuid not null, reason text not null,
  created_at timestamptz not null default now(), primary key (run_id, evidence_id));
alter table pipeline.retention_file_queue enable row level security;
alter table pipeline.retention_evidence_skips enable row level security;
revoke all on pipeline.retention_file_queue, pipeline.retention_evidence_skips from public, anon, authenticated;

do $g$ begin
  if (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'security.retention_catalogue_v1()'::regprocedure) is distinct from 'df3b7f3b42b32f6afc80abf5e8dba338'
  or (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'security.retention_estimate_v1(text)'::regprocedure) is distinct from '3f99632eb32e0a46497f4d0163ba97cd'
  or (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'public.svc_retention_files_next(uuid, int)'::regprocedure) is distinct from '00fe36d17d337008a74a9ebc6820e34f'
  or (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'public.svc_retention_files_done(uuid, int, bigint, boolean, text)'::regprocedure) is distinct from '13e19eef72f3b2954c68c2d947d64f60' then
    raise exception 'a retention function is not the migration 0500/0600 definition; refusing to replace it';
  end if;
end $g$;

-- the candidates (before the per-batch re-check); used by the estimate and by the worker
create or replace function security.retention_evidence_candidates_v1()
returns table(evidence_id uuid, storage_path text, created_at timestamptz) language sql stable security definer set search_path to '' as $f$
  with a as (select r.started_at from pipeline.retention_runs r where r.category = 'evidence_audit' and r.status = 'done' order by r.finished_at desc limit 1)
  select e.id, e.storage_path, e.created_at
    from pipeline.evidence_artifacts e, a
   where e.created_at < least(a.started_at, now() - interval '7 days')
     and coalesce(e.retention_class, '') not in ('standard_365', 'source_evidence')
     and not exists (select 1 from pipeline.evidence_audit_refs r where r.evidence_id = e.id)
$f$;
revoke all on function security.retention_evidence_candidates_v1() from public, anon, authenticated;

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
      'rule', 'Count only: evidence records and files not referenced by any value, decision or pipeline record. Nothing is deleted. Run it before purging unreferenced evidence.'),
    jsonb_build_object('key', 'evidence_unreferenced', 'label', 'Unreferenced evidence', 'kind', 'files', 'purge', true,
      'rule', 'Evidence records and their files that the last completed audit found referenced nowhere, created before that audit and more than 7 days ago. Each batch is checked again just before removal; anything referenced by then is skipped. Evidence kept for 365 days by policy and ranking publisher source files are never purged. A file shared with another evidence record is kept.'))
$f$;

create or replace function security.retention_estimate_v1(p_cat text)
returns void language plpgsql security definer set search_path to '' as $f$
declare v_size bigint; v_rows bigint; v_bytes bigint; v_detail jsonb := '{}'::jsonb;
begin
  if p_cat = 'adapter_screenshots' then
    select coalesce(sum((o.metadata->>'size')::bigint), 0), count(*) filter (where o.created_at < now() - interval '7 days'),
           coalesce(sum((o.metadata->>'size')::bigint) filter (where o.created_at < now() - interval '7 days'), 0)
      into v_size, v_rows, v_bytes from storage.objects o where o.bucket_id = 'adapter-captures';
  elsif p_cat = 'retired_layer2' then
    select sum(pg_total_relation_size(t::regclass)) into v_size
      from unnest(array['pipeline.layer2_provider_trial_results', 'pipeline.layer2_course_discovery_candidates', 'pipeline.layer2_provider_attempts',
                        'pipeline.layer2_scale_qualification_items', 'pipeline.layer2_scope_wave_items']) t;
    v_rows := (select count(*) from pipeline.layer2_provider_trial_results) + (select count(*) from pipeline.layer2_course_discovery_candidates)
            + (select count(*) from pipeline.layer2_provider_attempts) + (select count(*) from pipeline.layer2_scale_qualification_items)
            + (select count(*) from pipeline.layer2_scope_wave_items);
    v_bytes := v_size;
    v_detail := jsonb_build_object('trial_results', (select count(*) from pipeline.layer2_provider_trial_results), 'discovery_candidates', (select count(*) from pipeline.layer2_course_discovery_candidates),
      'provider_attempts', (select count(*) from pipeline.layer2_provider_attempts), 'scale_qualification_items', (select count(*) from pipeline.layer2_scale_qualification_items),
      'scope_wave_items', (select count(*) from pipeline.layer2_scope_wave_items));
  elsif p_cat = 'job_log' then
    v_size := pg_total_relation_size('cron.job_run_details');
    select count(*) filter (where d.start_time < now() - interval '7 days'), count(*) into v_rows, v_bytes from cron.job_run_details d;
    v_bytes := case when v_bytes > 0 then v_size * v_rows / v_bytes else 0 end;
  elsif p_cat = 'directory_urls' then
    v_size := pg_total_relation_size('pipeline.coverage_provider_urls');
    with h as (select provider_id, substring(url from '^https?://(?:www\.)?([^/:?#]+)') host from pipeline.coverage_provider_urls),
         shared as (select host from h group by host having count(distinct provider_id) >= 3)
    select coalesce(jsonb_agg(host order by host), '[]'::jsonb) into v_detail from shared;
    v_detail := jsonb_build_object('hosts', v_detail);
    select count(*) into v_rows from pipeline.coverage_provider_urls u join catalogue.providers p on p.id = u.provider_id
     where substring(u.url from '^https?://(?:www\.)?([^/:?#]+)') in (select jsonb_array_elements_text(v_detail->'hosts'))
       and (p.website is null or p.website not ilike '%' || substring(u.url from '^https?://(?:www\.)?([^/:?#]+)') || '%')
       and not exists (select 1 from pipeline.coverage_course_pages pg where pg.url = u.url);
    v_bytes := case when (select reltuples from pg_class where oid = 'pipeline.coverage_provider_urls'::regclass) > 0
                    then (v_size * v_rows / greatest(1, (select reltuples from pg_class where oid = 'pipeline.coverage_provider_urls'::regclass)))::bigint else 0 end;
  elsif p_cat = 'evidence_audit' then
    v_size := pg_total_relation_size('pipeline.evidence_artifacts');
    select count(*), count(*) filter (where c.done_at is not null) into v_rows, v_bytes from pipeline.evidence_audit_columns c;
    v_detail := jsonb_build_object('columns', v_rows, 'columns_done', v_bytes, 'references', (select count(*) from pipeline.evidence_audit_refs),
      'evidence_records', (select count(*) from pipeline.evidence_artifacts),
      'evidence_files_bytes', (select coalesce(sum((o.metadata->>'size')::bigint), 0) from storage.objects o where o.bucket_id = 'evidence'));
    if v_rows > 0 and v_rows = v_bytes then
      select count(*), coalesce(sum((o.metadata->>'size')::bigint), 0) into v_rows, v_bytes
        from pipeline.evidence_artifacts e left join storage.objects o on o.bucket_id = 'evidence' and o.name = e.storage_path
       where not exists (select 1 from pipeline.evidence_audit_refs r where r.evidence_id = e.id);
    else
      v_rows := null; v_bytes := null;
    end if;
  elsif p_cat = 'evidence_unreferenced' then
    v_size := pg_total_relation_size('pipeline.evidence_artifacts');
    if exists (select 1 from pipeline.retention_runs r where r.category = 'evidence_audit' and r.status = 'done')
       and not exists (select 1 from pipeline.retention_runs r where r.category = 'evidence_audit' and r.status in ('queued', 'running')) then
      select count(*), coalesce(sum(s.sz), 0) into v_rows, v_bytes
        from security.retention_evidence_candidates_v1() c
        left join lateral (select (o.metadata->>'size')::bigint sz from storage.objects o where o.bucket_id = 'evidence' and o.name = c.storage_path) s on true;
      v_detail := (select jsonb_build_object('audit_run', r.id, 'audit_started_at', r.started_at, 'audit_finished_at', r.finished_at)
                     from pipeline.retention_runs r where r.category = 'evidence_audit' and r.status = 'done' order by r.finished_at desc limit 1);
    else
      v_rows := null; v_bytes := null; v_detail := jsonb_build_object('note', 'Run the evidence audit first (and let it finish).');
    end if;
  else
    raise exception 'unknown category';
  end if;
  insert into pipeline.retention_estimates(category, size_bytes, purgeable_rows, purgeable_bytes, detail, measured_at)
  values (p_cat, v_size, v_rows, v_bytes, v_detail, now())
  on conflict (category) do update set size_bytes = excluded.size_bytes, purgeable_rows = excluded.purgeable_rows, purgeable_bytes = excluded.purgeable_bytes,
         detail = excluded.detail, measured_at = excluded.measured_at;
end $f$;

create or replace function public.svc_retention_files_next(p_run_id uuid, p_limit int default 100)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_cat text; v_out jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select category into v_cat from pipeline.retention_runs where id = p_run_id and status = 'running';
  if v_cat = 'adapter_screenshots' then
    return coalesce((select jsonb_agg(jsonb_build_object('name', o.name, 'size', (o.metadata->>'size')::bigint, 'bucket', 'adapter-captures'))
                       from (select name, metadata from storage.objects where bucket_id = 'adapter-captures' and created_at < now() - interval '7 days' order by created_at limit least(greatest(p_limit, 1), 200)) o), '[]'::jsonb);
  elsif v_cat = 'evidence_unreferenced' then
    with h as (
      update pipeline.retention_file_queue q set status = 'handed', handed_at = now()
       where q.id in (select id from pipeline.retention_file_queue where run_id = p_run_id and status = 'queued' order by id limit least(greatest(p_limit, 1), 200))
      returning q.name, q.size, q.bucket)
    select coalesce(jsonb_agg(jsonb_build_object('name', name, 'size', size, 'bucket', bucket)), '[]'::jsonb) into v_out from h;
    return v_out;
  end if;
  return '[]'::jsonb;
end $f$;

create or replace function public.svc_retention_files_done(p_run_id uuid, p_removed int, p_bytes bigint, p_finished boolean, p_error text default null)
returns text language plpgsql security definer set search_path to '' as $f$
declare v_cat text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select category into v_cat from pipeline.retention_runs where id = p_run_id;
  if v_cat = 'evidence_unreferenced' then
    -- records are counted by the background worker when they are removed; here only file bytes and the queue are updated, and the run
    -- stays running until no candidate is left (the background worker finishes it)
    if p_error is null then
      update pipeline.retention_file_queue set status = 'removed' where run_id = p_run_id and status = 'handed';
    end if;
    update pipeline.retention_runs
       set bytes = bytes + greatest(coalesce(p_bytes, 0), 0), updated_at = now(),
           status = case when p_error is not null then 'failed' else status end,
           error = coalesce(left(p_error, 500), error),
           finished_at = case when p_error is not null then now() else finished_at end,
           note = case when p_error is not null then 'Failed while removing evidence files.'
                       else format('Running: %s records removed, %s MB of files so far.', removed, round((bytes + greatest(coalesce(p_bytes, 0), 0)) / 1e6)) end
     where id = p_run_id and status = 'running';
    return 'ok';
  end if;
  update pipeline.retention_runs
     set removed = removed + greatest(coalesce(p_removed, 0), 0), bytes = bytes + greatest(coalesce(p_bytes, 0), 0), updated_at = now(),
         status = case when p_error is not null then 'failed' when p_finished then 'done' else status end,
         error = coalesce(left(p_error, 500), error),
         finished_at = case when p_error is not null or p_finished then now() else finished_at end,
         note = case when p_error is not null then 'Failed while removing files.' when p_finished then format('Done: %s files removed (%s MB).', removed + greatest(coalesce(p_removed, 0), 0), round((bytes + greatest(coalesce(p_bytes, 0), 0)) / 1e6))
                     else format('Removing files: %s so far (%s MB).', removed + greatest(coalesce(p_removed, 0), 0), round((bytes + greatest(coalesce(p_bytes, 0), 0)) / 1e6)) end
   where id = p_run_id and status = 'running';
  if p_finished then perform security.retention_estimate_v1('adapter_screenshots'); end if;
  return 'ok';
end $f$;

revoke all on function security.retention_estimate_v1(text) from public, anon, authenticated;
revoke all on function public.svc_retention_files_next(uuid, int), public.svc_retention_files_done(uuid, int, bigint, boolean, text) from public, anon, authenticated;
grant execute on function public.svc_retention_files_next(uuid, int), public.svc_retention_files_done(uuid, int, bigint, boolean, text) to service_role;
