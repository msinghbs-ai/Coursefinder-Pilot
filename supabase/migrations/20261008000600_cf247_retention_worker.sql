-- CF-247, 8 Oct 2026: storage and retention, part 2 of 3: estimates and the background worker. Runs only what a Platform Admin queued on the
-- Storage & retention screen, in small batches, and logs every batch. Files (adapter screenshots) are removed through Storage by the
-- coverage-sweep worker (mode retention_files); this function never deletes storage rows itself.
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
  else
    raise exception 'unknown category';
  end if;
  insert into pipeline.retention_estimates(category, size_bytes, purgeable_rows, purgeable_bytes, detail, measured_at)
  values (p_cat, v_size, v_rows, v_bytes, v_detail, now())
  on conflict (category) do update set size_bytes = excluded.size_bytes, purgeable_rows = excluded.purgeable_rows, purgeable_bytes = excluded.purgeable_bytes,
         detail = excluded.detail, measured_at = excluded.measured_at;
end $f$;

create or replace function security.retention_tick_v1()
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare r pipeline.retention_runs%rowtype; v_n bigint := 0; v_cat text; v_hosts text[]; v_t text; v_col record; v_done int := 0;
begin
  -- keep the estimates fresh (one category per run, oldest first)
  select c->>'key' into v_cat from jsonb_array_elements(security.retention_catalogue_v1()) c
   left join pipeline.retention_estimates e on e.category = c->>'key'
   where c->>'key' <> 'evidence_audit' and (e.measured_at is null or e.measured_at < now() - interval '1 hour')
   order by e.measured_at nulls first limit 1;
  if v_cat is not null then perform security.retention_estimate_v1(v_cat); end if;

  select * into r from pipeline.retention_runs where status in ('queued', 'running') order by created_at limit 1 for update skip locked;
  if r.id is null then return jsonb_build_object('idle', true); end if;
  begin
    if r.status = 'queued' then
      perform security.retention_estimate_v1(r.category);
      update pipeline.retention_runs set status = 'running', started_at = now(), estimate = (select to_jsonb(e) from pipeline.retention_estimates e where e.category = r.category),
             note = 'Running in small batches.', updated_at = now() where id = r.id;
      if r.category = 'evidence_audit' then
        delete from pipeline.evidence_audit_refs;
        delete from pipeline.evidence_audit_columns;
        insert into pipeline.evidence_audit_columns(tbl, col)
        select distinct format('%I.%I', n.nspname, c.relname), a.attname
          from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
         where c.relkind = 'r' and a.attnum > 0 and not a.attisdropped and a.atttypid = 'uuid'::regtype
           and n.nspname in ('catalogue', 'pipeline', 'scholarship', 'ranking', 'workflow', 'pim', 'search')
           and (a.attname in ('evidence_id', 'evidence_artifact_id', 'source_artifact_id', 'supersedes_evidence_id') or a.attname like '%\_evidence\_id' escape '\')
           and c.relname not in ('evidence_audit_refs');
      end if;
      return jsonb_build_object('started', r.id);
    end if;

    if r.category = 'job_log' then
      delete from cron.job_run_details where runid in (select d.runid from cron.job_run_details d where d.start_time < now() - interval '7 days' limit 20000);
      get diagnostics v_n = row_count;
    elsif r.category = 'retired_layer2' then
      foreach v_t in array array['pipeline.layer2_provider_trial_results', 'pipeline.layer2_course_discovery_candidates', 'pipeline.layer2_provider_attempts',
                                 'pipeline.layer2_scale_qualification_items', 'pipeline.layer2_scope_wave_items'] loop
        execute format('delete from %s where ctid = any(array(select ctid from %s limit 5000))', v_t, v_t);
        get diagnostics v_n = row_count;
        exit when v_n > 0;
      end loop;
    elsif r.category = 'directory_urls' then
      select array(select jsonb_array_elements_text(coalesce(r.estimate->'detail'->'hosts', '[]'::jsonb))) into v_hosts;
      delete from pipeline.coverage_provider_urls where id in (
        select u.id from pipeline.coverage_provider_urls u join catalogue.providers p on p.id = u.provider_id
         where substring(u.url from '^https?://(?:www\.)?([^/:?#]+)') = any(v_hosts)
           and (p.website is null or p.website not ilike '%' || substring(u.url from '^https?://(?:www\.)?([^/:?#]+)') || '%')
           and not exists (select 1 from pipeline.coverage_course_pages pg where pg.url = u.url)
         limit 20000);
      get diagnostics v_n = row_count;
    elsif r.category = 'adapter_screenshots' then
      -- files go through Storage: hand the run to the worker; it reports back with svc_retention_files_done
      if r.note is distinct from 'Removing files through Storage.' or r.updated_at < now() - interval '10 minutes' then
        update pipeline.retention_runs set note = 'Removing files through Storage.', updated_at = now() where id = r.id;
        perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'retention_files', 'run_id', r.id));
      end if;
      return jsonb_build_object('handed_to_worker', r.id);
    elsif r.category = 'evidence_audit' then
      for v_col in select * from pipeline.evidence_audit_columns where done_at is null order by tbl, col limit 3 loop
        execute format('insert into pipeline.evidence_audit_refs(evidence_id) select distinct %I from %s where %I is not null on conflict do nothing', v_col.col, v_col.tbl, v_col.col);
        get diagnostics v_n = row_count;
        update pipeline.evidence_audit_columns set done_at = now(), rows_found = v_n where tbl = v_col.tbl and col = v_col.col;
        v_done := v_done + 1;
      end loop;
      if v_done = 0 then
        perform security.retention_estimate_v1('evidence_audit');
        update pipeline.retention_runs set status = 'done', finished_at = now(), updated_at = now(),
               removed = 0, estimate = (select to_jsonb(e) from pipeline.retention_estimates e where e.category = 'evidence_audit'),
               note = format('Audit complete: %s evidence records are not referenced anywhere (%s MB of files). Nothing was deleted.',
                             (select purgeable_rows from pipeline.retention_estimates where category = 'evidence_audit'),
                             round(coalesce((select purgeable_bytes from pipeline.retention_estimates where category = 'evidence_audit'), 0) / 1e6))
         where id = r.id;
      else
        update pipeline.retention_runs set note = format('Auditing: %s of %s reference columns done.', (select count(*) from pipeline.evidence_audit_columns where done_at is not null),
               (select count(*) from pipeline.evidence_audit_columns)), updated_at = now() where id = r.id;
      end if;
      return jsonb_build_object('audited_columns', v_done);
    end if;

    if v_n = 0 then
      perform security.retention_estimate_v1(r.category);
      update pipeline.retention_runs set status = 'done', finished_at = now(), updated_at = now(), note = format('Done: %s rows removed.', removed) where id = r.id;
    else
      update pipeline.retention_runs set removed = removed + v_n, note = format('Running: %s rows removed so far.', removed + v_n), updated_at = now() where id = r.id;
    end if;
    return jsonb_build_object('run', r.id, 'removed', v_n);
  exception when others then
    update pipeline.retention_runs set status = 'failed', error = left(sqlerrm, 500), finished_at = now(), updated_at = now() where id = r.id;
    return jsonb_build_object('failed', r.id, 'error', sqlerrm);
  end;
end $f$;

create or replace function public.svc_retention_files_next(p_run_id uuid, p_limit int default 100)
returns jsonb language plpgsql security definer set search_path to '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if not exists (select 1 from pipeline.retention_runs where id = p_run_id and category = 'adapter_screenshots' and status = 'running') then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('name', o.name, 'size', (o.metadata->>'size')::bigint))
                     from (select name, metadata from storage.objects where bucket_id = 'adapter-captures' and created_at < now() - interval '7 days' order by created_at limit least(greatest(p_limit, 1), 200)) o), '[]'::jsonb);
end $f$;

create or replace function public.svc_retention_files_done(p_run_id uuid, p_removed int, p_bytes bigint, p_finished boolean, p_error text default null)
returns text language plpgsql security definer set search_path to '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
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

revoke all on function security.retention_estimate_v1(text), security.retention_tick_v1() from public, anon, authenticated;
revoke all on function public.svc_retention_files_next(uuid, int), public.svc_retention_files_done(uuid, int, bigint, boolean, text) from public, anon, authenticated;
grant execute on function public.svc_retention_files_next(uuid, int), public.svc_retention_files_done(uuid, int, bigint, boolean, text) to service_role;
