-- CF-247, 8 Oct 2026: the Unreferenced evidence estimate counted each record's file size, so files shared between records were
-- counted more than once and files still used by kept records were included (estimate 1,686 MB; the first purge removed 541 MB, the
-- correct amount under the rule). The bytes now count each file once and only files no kept record uses. Estimate only; the purge
-- rule is unchanged. Replaces security.retention_estimate_v1 (migration 1200) behind an md5 guard.
do $g$ begin
  if (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'security.retention_estimate_v1(text)'::regprocedure) is distinct from '7dc43cdda07ecc1835536f3156e0ea20' then
    raise exception 'retention_estimate_v1 is not the migration 1200 definition; refusing to replace it';
  end if;
end $g$;
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
      -- bytes: each file once, and only files no other (kept) evidence record uses
      with c as materialized (select evidence_id, storage_path from security.retention_evidence_candidates_v1()),
           f as (select distinct storage_path from c where storage_path is not null)
      select (select count(*) from c),
             coalesce((select sum((o.metadata->>'size')::bigint) from f join storage.objects o on o.bucket_id = 'evidence' and o.name = f.storage_path
                        where not exists (select 1 from pipeline.evidence_artifacts e where e.storage_path = f.storage_path
                                            and not exists (select 1 from c where c.evidence_id = e.id))), 0)
        into v_rows, v_bytes;
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
revoke all on function security.retention_estimate_v1(text) from public, anon, authenticated;
