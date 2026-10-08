-- CF-247, 8 Oct 2026 (Platform Admin, "Add evidence purge to the screen"). Part 2 of 2, pasted in the SQL editor by the Platform Admin
-- (it removes rows, which the connector does not run). Widens the run category to evidence_unreferenced and teaches the background
-- worker (security.retention_tick_v1, replaced behind an md5 guard) to purge unreferenced evidence by the rule in part 1:
--   500 candidates a run (every 2 minutes); each batch is re-checked against every reference column of the last completed audit and
--   anything referenced is skipped and logged; a record still pointed to by a foreign key is skipped; files whose record was removed
--   and that no other evidence record uses are queued and removed through Storage by the coverage-sweep worker (mode retention_files).
do $g$ begin
  if (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'security.retention_tick_v1()'::regprocedure) is distinct from 'df48108133759772dd11367b9a847f38' then
    raise exception 'retention_tick_v1 is not the migration 0600 definition; refusing to replace it';
  end if;
  if to_regprocedure('security.retention_evidence_candidates_v1()') is null then raise exception 'apply migration 20261008001200 first'; end if;
end $g$;
alter table pipeline.retention_runs drop constraint retention_runs_category_check;
alter table pipeline.retention_runs add constraint retention_runs_category_check
  check (category in ('adapter_screenshots', 'retired_layer2', 'job_log', 'directory_urls', 'evidence_audit', 'evidence_unreferenced'));

create or replace function security.retention_tick_v1()
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare r pipeline.retention_runs%rowtype; v_n bigint := 0; v_cat text; v_hosts text[]; v_t text; v_col record; v_done int := 0;
        v_ev record; v_del int := 0; v_skip int := 0; v_q int := 0;
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
    elsif r.category = 'evidence_unreferenced' then
      -- files of the last batch still with the worker: hand them again if the worker has not reported for 10 minutes
      if exists (select 1 from pipeline.retention_file_queue q where q.run_id = r.id and q.status in ('queued', 'handed')) then
        if r.updated_at < now() - interval '10 minutes' or exists (select 1 from pipeline.retention_file_queue q where q.run_id = r.id and q.status = 'queued') then
          update pipeline.retention_file_queue set status = 'queued' where run_id = r.id and status = 'handed' and handed_at < now() - interval '10 minutes';
          update pipeline.retention_runs set updated_at = now() where id = r.id;
          perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'retention_files', 'run_id', r.id));
        end if;
        return jsonb_build_object('handed_to_worker', r.id);
      end if;
      if not exists (select 1 from pipeline.retention_runs a where a.category = 'evidence_audit' and a.status = 'done')
         or exists (select 1 from pipeline.retention_runs a where a.category = 'evidence_audit' and a.status in ('queued', 'running')) then
        raise exception 'Run the evidence audit first and let it finish.';
      end if;
      -- next batch: candidates not yet skipped in this run
      create temporary table ev_batch on commit drop as
        select c.evidence_id id, c.storage_path from security.retention_evidence_candidates_v1() c
         where not exists (select 1 from pipeline.retention_evidence_skips s where s.run_id = r.id and s.evidence_id = c.evidence_id)
         order by c.created_at limit 500;
      if not exists (select 1 from ev_batch) then
        perform security.retention_estimate_v1('evidence_unreferenced');
        update pipeline.retention_runs set status = 'done', finished_at = now(), updated_at = now(),
               note = format('Done: %s records and %s MB of files removed; %s skipped because they were referenced again.', removed, round(bytes / 1e6),
                             (select count(*) from pipeline.retention_evidence_skips s where s.run_id = r.id))
         where id = r.id;
        return jsonb_build_object('run', r.id, 'done', true);
      end if;
      -- re-check every reference column of the audit just before removal
      for v_col in select * from pipeline.evidence_audit_columns order by tbl, col loop
        execute format('insert into pipeline.retention_evidence_skips(run_id, evidence_id, reason) select %L::uuid, b.id, %L from pg_temp.ev_batch b where exists (select 1 from %s t where t.%I = b.id) on conflict do nothing',
                       r.id, 'referenced: ' || v_col.tbl || '.' || v_col.col, v_col.tbl, v_col.col);
      end loop;
      create temporary table ev_gone (storage_path text) on commit drop;
      for v_ev in select b.id, b.storage_path from ev_batch b
                   where not exists (select 1 from pipeline.retention_evidence_skips s where s.run_id = r.id and s.evidence_id = b.id) loop
        begin
          delete from pipeline.evidence_artifacts where id = v_ev.id;
          insert into ev_gone values (v_ev.storage_path);
          v_del := v_del + 1;
        exception when foreign_key_violation then
          insert into pipeline.retention_evidence_skips(run_id, evidence_id, reason) values (r.id, v_ev.id, 'still referenced (foreign key)') on conflict do nothing;
          v_skip := v_skip + 1;
        end;
      end loop;
      -- a file goes only when no remaining evidence record uses it
      insert into pipeline.retention_file_queue(run_id, bucket, name, size)
      select r.id, 'evidence', o.name, coalesce((o.metadata->>'size')::bigint, 0)
        from (select distinct storage_path from ev_gone where storage_path is not null) g
        join storage.objects o on o.bucket_id = 'evidence' and o.name = g.storage_path
       where not exists (select 1 from pipeline.evidence_artifacts e where e.storage_path = g.storage_path);
      get diagnostics v_q = row_count;
      update pipeline.retention_runs set removed = removed + v_del, updated_at = now(),
             note = format('Running: %s records removed, %s MB of files so far.', removed + v_del, round(bytes / 1e6)) where id = r.id;
      if v_q > 0 then perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'retention_files', 'run_id', r.id)); end if;
      return jsonb_build_object('run', r.id, 'removed', v_del, 'files_queued', v_q, 'skipped_fk', v_skip);
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

revoke all on function security.retention_tick_v1() from public, anon, authenticated;
