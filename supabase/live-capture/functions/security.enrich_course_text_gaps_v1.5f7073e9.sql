CREATE OR REPLACE FUNCTION security.enrich_course_text_gaps_v1(p_fields text[])
 RETURNS TABLE(provider_id uuid, course_id uuid, field text, pri integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int; v_days int := security.pipeline_num_v1('gaps.recheck_days', 60)::int;
        f text; v_room int; v_gmax int := security.pipeline_num_v1('enrich.course_description_pending_global_max', 0)::int;
        v_pmax int := security.pipeline_num_v1('enrich.course_description_pending_max', 10)::int; v_stamp text := security.course_description_machine_policy_stamp_v1();
begin
  foreach f in array array['description', 'deadline'] loop
    continue when not (f = any (coalesce(p_fields, '{}'::text[])));
    -- back-pressure (CF-247 C-DESC 8 Nov 2026): no new description readings while v_gmax descriptions already wait for a person (0 = off)
    continue when f = 'description' and v_gmax > 0
      and (select count(*) from pipeline.layer4_review_items q where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending') >= v_gmax;
    select v_cap - count(*) into v_room from pipeline.field_enrich_items e join pipeline.admin_jobs j on j.id = e.job_id
     where e.field = f and e.created_at > now() - interval '1 day' and coalesce((j.args->>'standing')::boolean, false);  -- fixed: the cap is a day's
    continue when coalesce(v_room, 0) <= 0;
    return query
      with miss as (
        select c.id cid, c.provider_id pid from catalogue.courses c
         where c.lifecycle_status = 'active'
           and case f when 'description' then nullif(btrim(c.description), '') is null else security.enrich_deadline_missing_v1(c.id) end
           -- read from the stored page only: the slice's rule (bound, or ambiguous with an identity proof, read)
           and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id and g.evidence_id is not null and g.status in ('bound', 'ambiguous')
                         and g.read_status = 'read' and g.identity_basis is not null)),
      last as (
        select distinct on (e.course_id) e.course_id cid, e.state, e.updated_at, e.reason,
               -- a reading held behind the provider's places that never recorded which model and prompt made it, and has no stored answer that proves it: it is read once more so the reader is recorded (the machine rule admits only a provable reader)
               (e.reason like 'held\_first\_admission:%' and nullif(e.value->'reader'->>'model', '') is null
                and not exists (select 1 from pipeline.enrich_ai_answers a where a.item_id = e.id and nullif(a.answer->>'model', '') is not null and nullif(a.answer->>'prompt_version', '') is not null
                                  and a.answer->'value'->'sentences' = e.value->'sentences')) unproven,
               -- cdesc-source-grounded-v1 (CF-247 F-CDESC, 12 Nov 2026): a description reading held by a check, or superseded in Layer 4, that an earlier prompt made is read once more with the released prompt
               -- (a reading held behind the provider's places passed its checks: it follows a decision through course_description_promote_held_v1 and is not read again here)
               -- 12 Nov 2026 (first-cycle check of #1047): a reading superseded in Layer 4, or marked reread: (a reading the worker mis-recorded, read again on a recorded decision), is read again whatever prompt made it
               (f = 'description' and e.state = 'skipped' and ((e.reason like 'held%' and e.reason not like 'held\_first\_admission:%'
                and coalesce(e.value->>'prompt_version', e.value->'reader'->>'prompt', '') <> security.cdesc_prompt_version_v1()) or e.reason like 'superseded:%' or e.reason like 'reread:%')) old_prompt
          from pipeline.field_enrich_items e where e.field = f and e.course_id in (select m.cid from miss m) order by e.course_id, e.id desc),
      -- a university whose every place for a first description is taken by a description that waits for a person (and that the machine has not declined for good) gets no new reading until one is decided
      full_p as (
        select c.provider_id pid from pipeline.layer4_review_items q join catalogue.courses c on c.id = q.entity_id
         where f = 'description' and q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending'
           and not exists (select 1 from pipeline.course_description_machine_admissions d where d.review_item_id = q.id and d.outcome = 'declined' and d.withdrawn_at is null and not d.transient and d.policy_stamp = v_stamp)
         group by 1 having count(*) >= v_pmax and not security.course_description_trusted_v1(c.provider_id)),
      pick as (
        select m.pid, m.cid, case when coalesce(l.unproven, false) then 0 when l.state is null or coalesce(l.old_prompt, false) then 1
                                  when exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.cid and g.read_at > l.updated_at) then 0 else 2 end pri
          from miss m left join last l on l.cid = m.cid
         where not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = m.cid and k.field in (f, 'all'))
           and coalesce(l.state, '') not in ('queued', 'waiting', 'ai', 'leased', 'review')
           and (l.state is null or l.state = 'filled' or l.reason = 'provider unpublished' or coalesce(l.unproven, false) or coalesce(l.old_prompt, false) or l.updated_at < now() - make_interval(days => v_days)
                or exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.cid and g.read_at > l.updated_at))
           and not security.enrich_item_held_v1(m.cid, f)
           and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = m.pid)
           and not exists (select 1 from full_p fp where fp.pid = m.pid))
      select z.pid, z.cid, f, z.pri
        from (select p.pid, p.cid, p.pri, row_number() over (partition by p.pid, p.pri order by p.cid) rn from pick p) z
       order by z.pri, z.rn, z.cid
       limit v_room;
  end loop;
end $function$
