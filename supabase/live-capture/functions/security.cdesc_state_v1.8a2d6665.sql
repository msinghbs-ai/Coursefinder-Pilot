CREATE OR REPLACE FUNCTION security.cdesc_state_v1(p_course_ids uuid[], p_provider uuid DEFAULT NULL::uuid)
 RETURNS TABLE(course_id uuid, provider_id uuid, title text, provider text, active boolean, has_description boolean, state text, source_ready boolean, source_reason text, source_url text, evidence_id uuid, page_read_at timestamp with time zone, page_next_read_at timestamp with time zone, last_item_id bigint, last_state text, last_reason text, last_attempt_at timestamp with time zone, last_job_id uuid, held_kind text, locked boolean, hidden boolean, waiting_for_person boolean, rejected_same_evidence boolean, machine_admitted boolean, human_decision boolean, next_retry_at timestamp with time zone, fill_block text, recheck_block text, release_flag_ids bigint[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with p as (select security.pipeline_num_v1('gaps.recheck_days', 60)::int days, security.cdesc_machine_ids_v1(p_course_ids) mach),
  c as (
    select co.id, co.provider_id, co.canonical_title ttl, co.lifecycle_status = 'active' act, nullif(btrim(co.description), '') is not null has_d
      from catalogue.courses co
     where (p_course_ids is not null and co.id = any (p_course_ids))
        or (p_provider is not null and co.provider_id = p_provider and co.lifecycle_status = 'active' and nullif(btrim(co.description), '') is null)),
  pg as (select g.course_id, g.url, g.status, g.read_status, g.identity_basis, g.evidence_id, g.read_at, g.next_read_at
           from pipeline.coverage_course_pages g where g.course_id in (select c0.id from c c0)),
  li as (select distinct on (e.course_id) e.course_id, e.id, e.state, e.reason, e.updated_at, e.evidence_id, e.job_id
           from pipeline.field_enrich_items e where e.field = 'description' and e.course_id in (select c0.id from c c0) order by e.course_id, e.id desc),
  fl as (select f.entity_key::uuid course_id,
                bool_or(f.state = 'raised' and f.reason_code = 'manual_hold') manual,
                bool_or(f.state = 'raised' and f.reason_code in ('enrich_no_value', 'manual_hold')) raised,
                -- the standing queue's wait (security.enrich_item_held_v1): a counting flag younger than gaps.recheck_days, unless the page was read again with new content since
                bool_or(f.state = 'counting' and f.reason_code = 'enrich_no_value' and f.flagged_at > now() - make_interval(days => p.days)
                        and not (pg0.evidence_id is not null and pg0.evidence_id::text is distinct from f.input_mark and pg0.read_at > f.flagged_at)) counting_any,
                array_agg(f.id) filter (where f.state = 'counting' and f.reason_code = 'enrich_no_value') counting_ids
           from pipeline.enrichment_flags f cross join p left join pg pg0 on pg0.course_id::text = f.entity_key
          where f.entity = 'course' and f.field in ('description', '') and f.entity_key in (select c0.id::text from c c0) group by f.entity_key),
  l4 as (select r.entity_id course_id, bool_or(r.status = 'pending') pending, bool_or(r.status in ('approved', 'edited_approved')) approved,
                array_agg(r.evidence_id) filter (where r.status = 'rejected' and r.evidence_id is not null) rejected_ev
           from pipeline.layer4_review_items r
          where r.entity_type = 'course' and r.field_code = 'course_description_first_read' and r.entity_id in (select c0.id from c c0) group by r.entity_id)
  select c.id, c.provider_id, c.ttl, coalesce(pr.display_name, pr.canonical_name), c.act, c.has_d, h.state,
         q.sr, q.sreason, pg.url, pg.evidence_id, pg.read_at, pg.next_read_at,
         li.id, li.state, li.reason, li.updated_at, li.job_id,
         case when coalesce(fl.manual, false) then 'manual_hold' when coalesce(fl.raised, false) then 'raised' when coalesce(fl.counting_any, false) then 'counting'
              when li.reason like 'held\_first\_admission%' then 'held_first_admission' when li.reason like 'held:%' then 'check' end,
         q.lk, q.hd, b.wait_person, b.rej, case when p.mach is null then null else c.id = any (p.mach) end, coalesce(l4.approved, false),
         case when c.has_d or not c.act or q.hd then null
              when not q.sr then pg.next_read_at
              when li.id is null or pg.read_at > li.updated_at then null
              else li.updated_at + make_interval(days => p.days) end,
         coalesce(b.cb, case when li.id is not null and not (li.state = 'filled' or li.reason = 'provider unpublished' or li.updated_at < now() - make_interval(days => p.days) or pg.read_at > li.updated_at)
                             then 'recent_attempt' when coalesce(fl.counting_any, false) then 'recent_attempt' end),
         coalesce(b.cb, case when li.state in ('skipped', 'failed') then null else 'nothing_to_recheck' end),
         fl.counting_ids
    from c cross join p
    left join catalogue.providers pr on pr.id = c.provider_id
    left join pg on pg.course_id = c.id left join li on li.course_id = c.id left join fl on fl.course_id = c.id left join l4 on l4.course_id = c.id
    cross join lateral (select exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field in ('description', 'course_description', 'all')) lk,
                               exists (select 1 from security.provider_hidden_v1 hh where hh.provider_id = c.provider_id) hd,
                               -- the standing queue's source rule (bound, or ambiguous with an identity proof, read, evidence) and the country rule the record step applies
                               (pg.course_id is not null and pg.evidence_id is not null and pg.status in ('bound', 'ambiguous') and pg.read_status = 'read' and pg.identity_basis is not null
                                and security.coverage_identity_allowed(c.provider_id, pg.identity_basis, 'description')) sr,
                               case when pg.course_id is null then 'no_page' when pg.status = 'mismatch' then 'page_mismatch' when pg.status not in ('bound', 'ambiguous') then 'page_not_bound'
                                    when pg.read_status is distinct from 'read' then 'page_not_read' when pg.evidence_id is null then 'no_evidence' when pg.identity_basis is null then 'no_identity_proof'
                                    when not security.coverage_identity_allowed(c.provider_id, pg.identity_basis, 'description') then 'identity_not_admitted' end sreason) q
    cross join lateral (select (li.state = 'review' or coalesce(l4.pending, false)) wait_person,
                               (l4.rejected_ev is not null and pg.evidence_id = any (l4.rejected_ev)) rej) b0
    cross join lateral (select b0.wait_person, coalesce(b0.rej, false) rej,
                               case when not c.act then 'not_active' when c.has_d then 'already_has_description' when q.lk then 'locked' when q.hd then 'provider_hidden' when not q.sr then 'no_source'
                                    when b0.wait_person then 'waiting_for_person' when li.state in ('queued', 'waiting', 'ai', 'leased') then 'in_flight'
                                    when coalesce(b0.rej, false) then 'rejected_same_evidence' when coalesce(fl.raised, false) then 'held_for_person'
                                    when li.reason like 'held\_first\_admission%' then 'held_first_admission'
                                    when (li.state = 'skipped' and li.evidence_id is not distinct from pg.evidence_id
                                          and li.reason in ('the page does not state it', 'the same page copy was read for this before and did not state it'))
                                         or security.field_absence_unchanged_v1(c.id, 'description', pg.evidence_id) then 'same_page_not_stated' end cb) b
    cross join lateral (select case when c.has_d then (case when p.mach is not null and c.id = any (p.mach) then 'machine_admitted' when coalesce(l4.approved, false) then 'human_decision' else 'present' end)
                                    when not c.act then 'inactive' when q.lk then 'locked' when b0.wait_person then 'ai_read' when li.state in ('queued', 'waiting', 'ai', 'leased') then 'queued'
                                    when not q.sr then 'missing' when li.state = 'failed' then 'failed'
                                    when li.state = 'skipped' and li.reason in ('the page does not state it', 'the same page copy was read for this before and did not state it') then 'not_stated'
                                    when li.state = 'skipped' then 'held' else 'source_ready' end state) h;
$function$
