CREATE OR REPLACE FUNCTION security.fee_reader_tick_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_added int := 0; v_queued int := 0; v_rejected int := 0; v_fired int := 0;
        v_max int := security.pipeline_num_v1('fees.max_pages_per_provider', 12)::int;
begin
  -- 23 Oct 2026: the job is called each minute and runs every fees.run_every_minutes minutes
  if (extract(epoch from date_trunc('minute', now())) / 60)::bigint % greatest(security.pipeline_num_v1('fees.run_every_minutes', 2)::int, 1) <> 0 then
    return jsonb_build_object('skipped', 'not this minute');
  end if;
  -- 1 fee pages suggested by the central-page search, for providers in scope
  insert into pipeline.provider_fact_sources(provider_id, kind, url, title, rank, found_via, status)
  select x.provider_id, 'fee_schedule', x.url, left(x.title, 200), 5, 'search', 'found'
    from (select s.provider_id, e->>'url' url, e->>'title' title, row_number() over (partition by s.provider_id order by (e->>'score')::numeric desc) rn
            from pipeline.provider_central_search s cross join lateral jsonb_array_elements(coalesce(s.found, '[]'::jsonb)) e
           where e->>'kind' = 'fee_schedule' and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('fees.min_suggest_score', 4)
             and security.fee_reader_in_scope_v1(s.provider_id)) x
   where x.rn <= v_max and x.url ~ '^https?://'
     and (select count(*) from pipeline.provider_fact_sources f where f.provider_id = x.provider_id and f.kind = 'fee_schedule') < v_max
  on conflict (provider_id, kind, url) do nothing;
  get diagnostics v_added = row_count;

  -- 2 queue every stored fee page version not read yet; a new version of a page read before is a finding
  insert into pipeline.fee_reader_queue(fact_source_id, provider_id, content_hash)
  select f.id, f.provider_id, f.content_hash
    from pipeline.provider_fact_sources f join pipeline.evidence_artifacts e on e.id = f.evidence_id
   where f.kind = 'fee_schedule' and f.content_hash is not null and e.storage_path is not null and f.status in ('read', 'no_values', 'parsed')
     and security.fee_reader_in_scope_v1(f.provider_id)
  on conflict (fact_source_id, content_hash) do nothing;
  get diagnostics v_queued = row_count;
  perform security.fee_reader_finding_v1(q.provider_id, q.fact_source_id, 'page_changed', q.fact_source_id::text, jsonb_build_object('url', f.url))
     from pipeline.fee_reader_queue q join pipeline.provider_fact_sources f on f.id = q.fact_source_id
    where q.state = 'queued' and q.created_at > now() - interval '15 minutes'  -- fixed: the tick runs every 10 minutes
      and exists (select 1 from pipeline.fee_reader_queue o where o.fact_source_id = q.fact_source_id and o.content_hash <> q.content_hash and o.state = 'done');

  -- 3 rows a person rejected or corrected in Layer 4 are findings the reader learns from
  with r as (
    select l.entity_id course_id, fr.provider_id, fr.qualification, l.status decision
      from pipeline.layer4_review_items l
      join pipeline.fee_reader_rows fr on fr.course_id = l.entity_id and fr.outcome = 'review'
     where l.field_code = 'provider_current_tuition_validation' and l.status in ('rejected', 'edited_approved') and l.layer2_state->>'source' = 'fee reader'
       and l.decided_at > now() - interval '1 day')  -- fixed: look-back longer than the 10-minute tick
  select count(*) into v_rejected from (
    select security.fee_reader_finding_v1(r.provider_id, null, 'rejected', r.course_id::text,
             jsonb_build_object('qualification', r.qualification, 'decision', r.decision)) from r) z;

  -- 2b course pages that show one international fee for a course with no fee held (CF-247 23 Oct 2026)
  v_queued := v_queued + security.fee_course_pages_enqueue_v1();

  -- 4 the worker, while there is work and AI budget
  if exists (select 1 from pipeline.fee_reader_queue q where q.state = 'queued' or (q.state = 'leased' and q.leased_until < now()))
     and not exists (select 1 from pipeline.fee_reader_queue q where q.state = 'leased' and q.leased_until > now())
     and security.ai_use_allowed_v1('fee_ai') then
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'fee_ai', 'limit', security.pipeline_num_v1('fees.pages_per_run', 3)::int, 'concurrency', security.pipeline_num_v1('fees.concurrency', 4)::int));
    v_fired := 1;
  end if;
  return jsonb_build_object('pages_added', v_added, 'queued', v_queued, 'rejected_seen', v_rejected, 'worker', v_fired);
end $function$
