-- CF-247 (Decision 215, 2 Oct 2026): Live activity shows errors that workers send back. The evidence link job's
-- scheduled run always "succeeded" (it only sends the request) while the worker refused it for two days; worker replies
-- (pg_net, kept a few hours) with an error status are now listed with their message and count, and the evidence link
-- job shows its last summary and the pages left to index. md5 guard on security.admin_live_activity_v1.

do $p$
declare s text; d text; v text; o text[]; n text[]; i int;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'admin_live_activity_v1';
  o := array[
    E'           (select count(*) from pipeline.layer3_work_items where task_class = ''provider_current_tuition_validation'' and completed_at > now() - interval ''24 hours'')),\n  jobs as (',
    $o$substring(j.command from '"mode":"([a-z_]+)"') worker_mode,$o$,
    $o$h.content like '%"mode":"' || m.mode || '"%'$o$,
    $o$    'in_flight', (select count(*) from net.http_request_queue)$o$];
  n := array[
    E'           (select count(*) from pipeline.layer3_work_items where task_class = ''provider_current_tuition_validation'' and completed_at > now() - interval ''24 hours'')\n'
    || E'    union all select ''evidence-link-index'', ''pages'',\n'
    || E'           (select count(*) from pipeline.evidence_artifacts e left join pipeline.evidence_link_index_state st on st.evidence_id = e.id\n'
    || E'              join pipeline.sources s on s.id = e.source_id join pipeline.layer2_onboarding_snapshot o on o.provider_id = s.provider_id\n'
    || E'             where e.storage_path is not null and e.storage_path !~ ''^[a-z-]+://''\n'
    || E'               and e.evidence_type in (''layer2_html_snapshot'',''layer2_extraction_input'',''source_snapshot'',''provider_contact_html_snapshot'')\n'
    || E'               and (e.mime_type ilike ''%html%'' or e.mime_type ilike ''%json%'')\n'
    || E'               and (st.evidence_id is null or (st.status = ''error'' and st.indexed_at < now() - interval ''6 hours''))),\n'
    || E'           (select count(*) from pipeline.evidence_link_index_state where status in (''indexed'',''no_links'') and indexed_at > now() - interval ''24 hours'')),\n  jobs as (',
    $n$coalesce(substring(j.command from '"mode":"([a-z_]+)"'), case a.jobname when 'evidence-link-index' then 'evidence_link_index' end) worker_mode,$n$,
    $n$(case when m.mode = 'evidence_link_index' then h.content like '%"processed":%"summary":{"indexed"%' else h.content like '%"mode":"' || m.mode || '"%' end)$n$,
    $n$    'in_flight', (select count(*) from net.http_request_queue),
    -- Decision 215: replies from workers with an error status (pg_net keeps them a few hours)
    'worker_errors', (select coalesce(jsonb_agg(jsonb_build_object('status', x.status_code, 'timed_out', x.timed_out, 'message', x.message, 'count', x.n, 'last', x.last) order by x.last desc), '[]'::jsonb)
                        from (select h.status_code, h.timed_out, left(coalesce(h.error_msg, h.content), 200) message, count(*) n, max(h.created) last
                                from net._http_response h where h.status_code >= 400 or h.status_code is null
                               group by 1, 2, 3 order by max(h.created) desc limit 10) x)$n$];
  v := md5(s);
  if v is distinct from '3ec199b1a612fd5c6c968ba6479de96f' then raise exception 'admin_live_activity_v1 changed (md5 %); not replacing', v; end if;
  for i in 1..array_length(o,1) loop
    if (length(d) - length(replace(d, o[i], ''))) / length(o[i]) <> 1 then raise exception 'live activity piece % not found once', i; end if;
    d := replace(d, o[i], n[i]);
  end loop;
  execute d;
end $p$;
