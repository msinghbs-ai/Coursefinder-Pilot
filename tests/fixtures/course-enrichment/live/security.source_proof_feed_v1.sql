CREATE OR REPLACE FUNCTION security.source_proof_feed_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 mandate 3 Nov 2026 12:04 §6 ("Treat missing page proof as a discoverable coverage gap, not a permanent silent skip"): job
-- source-proof-feed. Settles finished requests, then routes courses waiting for page proof (the gap queue's pipeline.course_page_proofs) to the
-- existing lane that can prove a page: course-relink (free) or course-page search (paid, proof.search_per_run, ships 0). Courses waiting on
-- Layer 4, locked by hand or still being read are recorded and left to that process. A course is tried at most proof.max_attempts times, and
-- again only when its input fingerprint changes.
declare v_free int := greatest(0, security.pipeline_num_v1('proof.feed_per_run', 50)::int);
        v_paid int := greatest(0, security.pipeline_num_v1('proof.search_per_run', 0)::int);
        v_max int := greatest(1, security.pipeline_num_v1('proof.max_attempts', 3)::int);
        v_scan int := greatest(1, security.pipeline_num_v1('proof.scan_per_run', 2000)::int);
        v_hold interval := make_interval(days => security.pipeline_num_v1('proof.request_hold_days', 7)::int);
        r record; v_route text; v_act boolean; n jsonb := '{}'::jsonb; v_settled int := 0; v_k int; v_t0 timestamptz := clock_timestamp();
begin
  -- 1. settle: the lane decided (or started again), or the request was not taken up in time
  update pipeline.source_proof_requests q set state = 'done', settled_at = now(), outcome = 'relink_' || x.state,
         detail = q.detail || jsonb_build_object('relink_reason', x.reason, 'result_url', x.result_url)
    from pipeline.course_relink x
   where q.state = 'queued' and q.route = 'relink' and x.course_id = q.course_id and coalesce(x.decided_at, x.started_at) >= q.requested_at;
  get diagnostics v_k = row_count; v_settled := v_settled + v_k;
  update pipeline.source_proof_requests q set state = 'done', settled_at = now(), outcome = 'search_' || s.state,
         detail = q.detail || jsonb_build_object('bound_url', s.bound_url)
    from pipeline.course_link_search s
   where q.state = 'queued' and q.route = 'search' and s.course_id = q.course_id and s.state in ('found', 'verified', 'none', 'error')
     and coalesce(s.done_at, s.sent_at, s.queued_at) >= q.requested_at;
  get diagnostics v_k = row_count; v_settled := v_settled + v_k;
  update pipeline.source_proof_requests q set state = 'done', settled_at = now(), outcome = 'not_taken'
   where q.state = 'queued' and q.requested_at < now() - v_hold;
  get diagnostics v_k = row_count; v_settled := v_settled + v_k;

  -- 2. consider courses waiting for page proof, least recently considered first
  for r in
    with w as (
      select pp.course_id, c.provider_id, c.course_code, pp.page_key, q.fingerprint qfp, coalesce(q.attempts, 0) attempts
        from pipeline.course_page_proofs pp
        join catalogue.courses c on c.id = pp.course_id and c.lifecycle_status = 'active'
        left join pipeline.source_proof_requests q on q.course_id = pp.course_id
       where not pp.proven and coalesce(q.state, '') <> 'queued'
         and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)
         and security.coverage_country(c.provider_id) in (select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s
                                                           where s.toolset_key = 'pipeline' and s.key = 'course_url.fill_countries')
       order by q.considered_at nulls first, pp.course_id
       limit v_scan),
    prov as materialized (
      select d.provider_id,
             (select count(*) from pipeline.coverage_provider_urls u where u.provider_id = d.provider_id)
             + (select count(*) from pipeline.provider_discovery_links l where l.provider_id = d.provider_id) lists,
             (select count(*) from pipeline.coverage_course_pages g where g.provider_id = d.provider_id and g.read_status = 'read' and g.status = 'bound' and g.identity_basis is not null) verified,
             (select rc.search_domain from pipeline.course_link_recipes rc where rc.provider_id = d.provider_id and rc.active) recipe,
             (select pp2.rank from pipeline.provider_priority pp2 where pp2.provider_id = d.provider_id) prank
        from (select distinct w.provider_id from w) d)
    select w.*, p.recipe, p.prank, g.status gstatus, g.read_status, coalesce(g.read_attempts, 0) read_attempts, s.state sstate,
           md5(concat_ws('|', w.page_key, p.lists, p.verified, p.recipe)) fp,
           exists (select 1 from pipeline.layer4_review_items i where i.entity_id = w.course_id and i.field_code = 'official_course_url' and i.status = 'pending') l4,
           exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = w.course_id and k.field in ('official_url', 'course_url', 'all')) locked
      from w join prov p on p.provider_id = w.provider_id
      left join pipeline.coverage_course_pages g on g.course_id = w.course_id
      left join pipeline.course_link_search s on s.course_id = w.course_id
     order by (coalesce(w.course_code, '') ~ '^[0-9]{6}[0-9A-Z]$') desc, coalesce(p.prank, 100000), w.course_id  -- fixed: the CRICOS code form; official source first
  loop
    v_act := false;
    v_route := case
      when r.l4 then 'layer4'
      when r.locked then 'locked'
      when r.gstatus in ('bound', 'ambiguous') and coalesce(r.read_status, '') in ('', 'deferred', 'fetch_failed', 'needs_render', 'blocked') and r.read_attempts < 3 then 'reading'  -- fixed: the read picker's own try limit
      when r.qfp = r.fp then 'unchanged'   -- tried with these inputs already (the fingerprint is kept from the last try)
      when r.attempts >= v_max then 'exhausted'
      when r.read_status = 'identity_mismatch' and v_free > 0 then 'relink'
      when r.read_status = 'identity_mismatch' then 'no_route'
      when r.recipe is not null and v_paid > 0 and coalesce(r.sstate, 'none') in ('none', 'error') then 'search'
      else 'no_route' end;
    if v_route = 'unchanged' then
      update pipeline.source_proof_requests set considered_at = now() where course_id = r.course_id;
    elsif v_route = 'relink' then
      v_free := v_free - 1; v_act := true;
    elsif v_route = 'search' then
      insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
      values (r.course_id, r.provider_id, case when coalesce(r.course_code, '') ~ '^[0-9]{6}[0-9A-Z]$' then 'cricos' else 'title' end, 'queued', now())  -- fixed: the CRICOS code form
      on conflict (course_id) do update set state = 'queued', stage = excluded.stage, attempts = 0, done_at = null, queued_at = now()
       where pipeline.course_link_search.state in ('none', 'error');
      v_paid := v_paid - 1; v_act := true;
    end if;
    if v_route <> 'unchanged' then
      insert into pipeline.source_proof_requests as q (course_id, provider_id, route, state, fingerprint, attempts, requested_at, settled_at, outcome, considered_at, detail)
      values (r.course_id, r.provider_id, v_route, case when v_act then 'queued' else 'held' end, case when v_act then r.fp end, r.attempts + case when v_act then 1 else 0 end,
              case when v_act then now() end, null, null, now(), jsonb_build_object('read_status', r.read_status, 'search', r.sstate))
      on conflict (course_id) do update set route = excluded.route, state = excluded.state, provider_id = excluded.provider_id,
             fingerprint = coalesce(excluded.fingerprint, q.fingerprint), attempts = excluded.attempts,
             requested_at = coalesce(excluded.requested_at, q.requested_at), settled_at = case when excluded.state = 'queued' then null else q.settled_at end,
             outcome = case when excluded.state = 'queued' then null else q.outcome end, considered_at = now(), detail = q.detail || excluded.detail;
    end if;
    n := jsonb_set(n, array[v_route], to_jsonb(coalesce((n->>v_route)::int, 0) + 1));
  end loop;
  return jsonb_build_object('settled', v_settled, 'routed', n, 'ms', (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);  -- fixed: milliseconds
end $function$
;
