-- CF-247 F-CDESC.06 / F-OPS (Platform Admin directive, 10 Nov 2026): "Fill description" and "Recheck description" on demand, through the EXISTING Enrich fields task engine.
-- Direction (docs/platform/nz-enrichment-brief/2026-11-10-course-descriptions-autonomous-ai-admission-decision.md, section 6): inside the Course Catalogue, the Course Detail blade and the
-- Provider Catalogue, one course, selected courses, or one university, with a bounded preview and a reason, without an alternative scheduler; the states Missing, Source-ready, AI-read, Held,
-- Machine-admitted, Human decision, Website feed, Zoho feed and Verified HTTP stay distinct, with the last attempt, next retry, source URL, evidence and the actual gain.
--
-- What this adds (no new job kind, no new scheduler, no new reader, no new table, no new setting):
--   1 security.cdesc_state_v1(course_ids, provider)   ONE read of where each course's description stands: the stored page (source URL, evidence, identity proof), the last Enrich fields item
--                                                     (state, reason, time), flags, hand locks, hidden provider, Layer 4 waits and rejections, the machine-admission ledger when it exists,
--                                                     the headline state, the next automatic retry, and the exact reason (a key) Fill and Recheck would each leave the course out.
--                                                     Eligibility is the standing gap queue's rule (security.enrich_course_text_gaps_v1) without its daily count; the two cannot disagree (the fixture proves it).
--   2 security.cdesc_on_demand_v1(action, args, rank, user)   preview, start and verify. Start makes an ordinary pipeline.admin_jobs row of kind enrich_fields (the engine, the worker, the
--                                                     AI guard, the daily AI cost guard and Task manager are unchanged) with its items, a reason, an audit line (admin_control_events) and an idempotency key (a repeat returns the same task).
--   3 public.admin_course_description_state_v1(course_ids)   the read-only per-course state for the screens (rank 3 and above).
--   4 public.admin_enrich_fields: ONE md5-guarded edit, a dispatch of the actions preview and start when the arguments carry mode (fill or recheck) or course_ids, and of verify, to security.cdesc_on_demand_v1.
--                                                     Every other action and every call without those arguments runs the old text unchanged.
-- Bounds (G2; no operational number is written here and no new setting is added, Platform Admin 10 Nov 2026 05:40): the courses of one request are at most the existing setting run_now.pilot_cap
--   (Run now: most courses in a cohort); the courses of a university request are at most the headroom left today under the existing setting enrich.course_text_items_per_day (the items already made today
--   for the description, by any route, are counted), so an on-demand request can never take more of the day's AI than the standing queue's own ceiling. The AI guard and the daily AI cost guard still stop the worker.
-- Recheck: re-queues a held, not-stated or failed description item NOW instead of after gaps.recheck_days. It releases only the counting flag (enrich_no_value) of the course's description through the
--   existing security.flag_release_v1 (a person's release, in the flag history). It NEVER bypasses: a hand lock, a rejection of the same page copy, a hidden university, a raised flag or manual hold, a page that is
--   not bound or read or proved (binding and identity checks, security.coverage_identity_allowed), a reading waiting for a person, a task already holding the course, or a page copy already verified not to state it
--   (security.field_absence_unchanged_v1). The worker still rejects a stale or mismatched copy at record time (security.enrich_course_text_record_v1, unchanged).
-- Verify (read only): for chosen courses it reads back catalogue.courses.description and public.website_v2_course(stable key)->item->description and reports, separately, Catalogue, Website feed, Zoho feed
--   (only for the countries in zoho.sync_countries; others are not applicable, never a failure; a Zoho course item that carries no description field is reported as not carried) and Verified HTTP
--   (not checked by the database: it cannot call the website; the release check does that; reported as not checked, never as passed or failed). Unknown is never zero.
-- Machine admission (agent D1, migration 20261110060000): Machine-admitted is shown only for a LIVE ledger row of pipeline.course_description_machine_admissions (outcome = 'admitted' and withdrawn_at is null).
--   A declined row, or an admission a person withdrew, does not count (a declined course a person then approved is Human decision). If the ledger is not there, or lacks course_id, outcome or withdrawn_at,
--   the answer is unknown (null), never false; there is no catch-all fallback.
-- Capacity: a request for chosen courses is at most least(run_now.pilot_cap, the day's room); a request for one university is at most the day's room. The standing queue's back-pressure
--   (enrich.course_description_pending_global_max, 0 = off) is honoured as well: while that many descriptions wait for a person in Layer 4, every course is left out as review_backlog. A person's request is not
--   exempt, because the reason for the limit (a reviewer who cannot keep up) is the same.
-- Concurrency: start takes advisory locks BEFORE it chooses the courses (one university: that university's lock; chosen courses: each course's lock, and each university's lock shared; always in sorted order),
--   then checks for a repeat, then chooses, then writes, so two requests (even with different keys) cannot queue the same course twice. The standing queue (security.field_gap_queue_tick_v1) takes no lock and
--   is not edited here: it keeps a course out when an open item is already COMMITTED, and so does this; the only gap left is a request that commits between that queue's read and its insert in one tick.
--   An idempotency key used again for a different mode or scope is refused, not answered with the other task.
-- Consumer API (G3): nothing in public.website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_*, svc_website_settings_v1, schema api or the five edge functions is altered, dropped, renamed or granted.
--   public.website_v2_course and pipeline.zoho_sync_items are READ by verify, exactly as the Data Delivery and Provider Catalogue facts read the feeds. Consumer API change approved: not applicable (no change).
-- Controls: all functions SECURITY DEFINER, search_path '', start needs rank 4 (Pipeline Operator) and a reason, preview and verify and state need rank 3 (Curator), as admin_enrich_fields has them.
-- Housekeeping: the edit of public.admin_enrich_fields is guarded by the md5 of the live body; if it differs the migration raises and nothing is applied. Forward recovery (md5 back to the production text,
--   byte for byte): supabase/held/cdesc_on_demand_forward_recovery.sql. Nothing is dropped, deleted or renamed by this migration.
-- Live definition this change edits (pg_proc.prosrc md5, read 10 Nov 2026 AEDT, project fxcwkweaxjtknorudmwp): public.admin_enrich_fields(text,jsonb) c9701d334b732a729a30a5147d9d016b -> f11db4466add68c4d7de5cb7c87d9bce
-- Replaces: nothing (public.admin_enrich_fields is edited in place; its Start card and the standing gap queue are unchanged)
-- Retires: nothing

do $g$
declare r record;
begin
  for r in select * from (values ('public.admin_enrich_fields(text,jsonb)'), ('security.pipeline_num_v1(text,numeric)'), ('security.current_role_rank()'), ('security.flag_release_v1(bigint,text,text,text,jsonb,boolean)'),
                                 ('security.enrich_item_in_flight_v1(uuid,uuid,text)'), ('security.field_absence_unchanged_v1(uuid,text,uuid)'), ('security.coverage_identity_allowed(uuid,text,text)'),
                                 ('security.enrich_unit_costs_v1()'), ('public.website_v2_course(text)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  for r in select * from (values ('pipeline.field_enrich_items'), ('pipeline.admin_jobs'), ('pipeline.admin_job_events'), ('pipeline.admin_control_events'), ('pipeline.coverage_course_pages'), ('pipeline.enrichment_flags'),
                                 ('pipeline.manual_locks'), ('pipeline.layer4_review_items'), ('pipeline.zoho_sync_items'), ('pipeline.platform_toolset_settings'), ('search.course_documents'), ('security.provider_hidden_v1')) v(rel) loop
    if to_regclass(r.rel) is null then raise exception 'required % is missing', r.rel; end if;
  end loop;
end $g$;

-- 1. the machine-admission ledger, when it exists (agent D1's route is not merged: unknown, never false) ---------------------------------------------------------
create or replace function security.cdesc_machine_ids_v1(p_ids uuid[]) returns uuid[]
language plpgsql stable security definer set search_path to '' as $function$
declare v uuid[]; v_rel regclass := to_regclass('pipeline.course_description_machine_admissions');
begin
  -- the ledger exists once the machine admission change is applied (20261110060000): course_id, outcome ('admitted' | 'declined') and withdrawn_at.
  -- Not there, or not that shape: unknown (null), which the screen shows as "not known", never as "no machine admission".
  if v_rel is null or (select count(*) from pg_attribute a where a.attrelid = v_rel and a.attname in ('course_id', 'outcome', 'withdrawn_at') and not a.attisdropped) <> 3 then return null; end if;
  -- only a live admission counts: a declined row, or an admission a person later withdrew, is not "Machine-admitted" (a declined course a person then approved is "Human decision")
  execute 'select coalesce(array_agg(distinct m.course_id), ''{}''::uuid[]) from pipeline.course_description_machine_admissions m where m.course_id = any ($1) and m.outcome = ''admitted'' and m.withdrawn_at is null' into v using p_ids;
  return v;
end $function$;

-- 2. the reason a course is left out, in plain words and with the next action ------------------------------------------------------------------------------------
create or replace function security.cdesc_block_info_v1(p_key text) returns jsonb
language sql immutable set search_path to '' as $function$
  select case p_key
    when 'not_active' then jsonb_build_object('label', 'Not an active course', 'next', 'Nothing to do.')
    when 'already_has_description' then jsonb_build_object('label', 'Already has a description', 'next', 'Nothing to fill.')
    when 'locked' then jsonb_build_object('label', 'Locked by hand', 'next', 'A person removes the lock first; a read never overwrites a hand-held value.')
    when 'provider_hidden' then jsonb_build_object('label', 'The university is unpublished', 'next', 'Publish the university again, then run this.')
    when 'no_source' then jsonb_build_object('label', 'No stored course page that is proved to be this course', 'next', 'Wait for the course page to be found and read, or add a course link. Nothing is read from a generic page.')
    when 'waiting_for_person' then jsonb_build_object('label', 'A reading is waiting for a person in Layer 4', 'next', 'Decide it in Layer 4.')
    when 'in_flight' then jsonb_build_object('label', 'Already in an open task', 'next', 'Wait for that task to finish.')
    when 'rejected_same_evidence' then jsonb_build_object('label', 'A person rejected the reading of this same page copy', 'next', 'It is read again when the page is read again.')
    when 'held_for_person' then jsonb_build_object('label', 'Held for a person (flag raised or manual hold)', 'next', 'Release the flag in Flags, or wait for the page to be read again.')
    when 'held_first_admission' then jsonb_build_object('label', 'Read and checked; waits for the university''s first descriptions to be decided', 'next', 'Decide the waiting readings in Layer 4; no new read is needed.')
    when 'same_page_not_stated' then jsonb_build_object('label', 'This same page copy was read and does not state it', 'next', 'It is read again when the page is read again.')
    when 'recent_attempt' then jsonb_build_object('label', 'Tried recently', 'next', 'The standing queue tries again on its own date; use Recheck description to read it now.')
    when 'nothing_to_recheck' then jsonb_build_object('label', 'Not tried yet', 'next', 'Use Fill description.')
    when 'review_backlog' then jsonb_build_object('label', 'Too many descriptions already wait for a person in Layer 4', 'next', 'Decide the waiting readings in Layer 4; the limit is Pipeline settings > Course description: most waiting for a person before new readings pause.')
    when 'daily_capacity' then jsonb_build_object('label', 'Over today''s limit for description readings', 'next', 'The limit is Pipeline settings > Enrich fields > items per day; it frees as the day moves on.')
    when null then null
    else jsonb_build_object('label', p_key, 'next', '') end
$function$;

-- 3. where each course's description stands (one read; used by the screens, preview, start and the fixture) ------------------------------------------------------------
create or replace function security.cdesc_state_v1(p_course_ids uuid[], p_provider uuid default null)
returns table (course_id uuid, provider_id uuid, title text, provider text, active boolean, has_description boolean, state text,
               source_ready boolean, source_reason text, source_url text, evidence_id uuid, page_read_at timestamptz, page_next_read_at timestamptz,
               last_item_id bigint, last_state text, last_reason text, last_attempt_at timestamptz, last_job_id uuid,
               held_kind text, locked boolean, hidden boolean, waiting_for_person boolean, rejected_same_evidence boolean,
               machine_admitted boolean, human_decision boolean, next_retry_at timestamptz, fill_block text, recheck_block text, release_flag_ids bigint[])
language sql stable security definer set search_path to '' as $function$
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
$function$;

-- 4. preview, start, verify -----------------------------------------------------------------------------------------------------------------------------------
create or replace function security.cdesc_on_demand_v1(p_action text, p_args jsonb, p_rank int, p_uid uuid) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare
  a jsonb := coalesce(p_args, '{}'::jsonb);
  v_mode text := lower(btrim(coalesce(a->>'mode', '')));
  v_ids uuid[] := array(select distinct x::uuid from jsonb_array_elements_text(case when jsonb_typeof(a->'course_ids') = 'array' then a->'course_ids' else '[]'::jsonb end) x);
  v_pids uuid[] := array(select distinct x::uuid from jsonb_array_elements_text(case when jsonb_typeof(a->'provider_ids') = 'array' then a->'provider_ids' else '[]'::jsonb end) x);
  v_max int := security.pipeline_num_v1('run_now.pilot_cap', 20)::int;
  v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int;
  v_vmax constant int := 10; -- fixed: the read-back calls public.website_v2_course for each course (about 255 ms each), so ten stay inside the 8 second request limit
  v_used int; v_room int; v_scope text; v_limit int; v_reason text; v_key text; v_given boolean; v_job uuid; v_n int; v_total int; v_elig int;
  v_blocks jsonb; v_sel uuid[]; v_providers uuid[]; v_flags bigint[]; f bigint; v_title text; v_usd numeric; v_rows jsonb; v_missing uuid[]; v_ex pipeline.admin_jobs%rowtype; v_ptitle text; v_zoho jsonb;
  r record; v_web jsonb; v_wst text; v_zst text; v_wnote text; v_znote text;
begin
  if p_action = 'verify' then
    if coalesce(p_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
    if cardinality(v_ids) = 0 then raise exception 'choose the courses to check'; end if;
    if cardinality(v_ids) > v_vmax then raise exception 'check at most % courses at a time', v_vmax; end if;
    v_zoho := coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'zoho.sync_countries'), '["AU"]'::jsonb); -- fixed: the Zoho feed's own default country (security.zoho_sync_item_v1)
    v_rows := '[]'::jsonb;
    for r in select co.id, nullif(btrim(co.description), '') descr, k.iso_alpha2::text cc, d.course_stable_key sk
               from catalogue.courses co join catalogue.providers pr on pr.id = co.provider_id join ref.countries k on k.id = pr.country_id
               left join lateral (select d0.course_stable_key from search.course_documents d0 where d0.course_id = co.id limit 1) d on true
              where co.id = any (v_ids) order by co.id loop
      v_wst := null; v_zst := null; v_wnote := null; v_znote := null;
      if r.descr is null then
        v_wst := 'not_applicable'; v_wnote := 'The catalogue holds no description, so there is nothing to carry.';
        v_zst := 'not_applicable'; v_znote := v_wnote;
      else
        if r.sk is null then v_wst := 'pending'; v_wnote := 'The course is not in the published search set yet.';
        else
          begin
            v_web := public.website_v2_course(r.sk);
            v_wst := case when v_web->'item'->>'description' is null then 'missing' when v_web->'item'->>'description' = r.descr then 'matched' else 'differs' end;
            v_wnote := case v_wst when 'matched' then 'The Website API returns the same words as the catalogue.' when 'missing' then 'The Website API returns no description for this course.' else 'The Website API returns different words from the catalogue.' end;
          exception when others then
            v_wst := 'unknown'; v_wnote := 'The read-back failed: ' || left(sqlerrm, 160); -- fixed: the length of an error shown to a person
          end;
        end if;
        if not (v_zoho ? r.cc) then v_zst := 'not_applicable'; v_znote := 'The country is not synced to Zoho (zoho.sync_countries).';
        elsif r.sk is null then v_zst := 'pending'; v_znote := 'The course is not in the published search set yet.';
        else
          select case when z.item_key is null then 'pending' when z.item ? 'description' then (case when z.item->>'description' = r.descr then 'matched' else 'differs' end) else 'not_carried' end
            into v_zst from (select 1) one left join pipeline.zoho_sync_items z on z.entity = 'course' and z.item_key = r.sk and z.removed_at is null;
          v_znote := case v_zst when 'pending' then 'The course is not in the Zoho course feed yet.' when 'matched' then 'The Zoho course item holds the same words.'
                                when 'differs' then 'The Zoho course item holds different words.' else 'The Zoho course item has no description field, so Zoho does not receive it from this feed.' end;
        end if;
      end if;
      v_rows := v_rows || jsonb_build_array(jsonb_build_object('course_id', r.id, 'stable_key', r.sk, 'country', r.cc,
        'catalogue', jsonb_build_object('state', case when r.descr is null then 'missing' else 'present' end, 'chars', length(r.descr)),
        'website', jsonb_build_object('state', v_wst, 'note', v_wnote), 'zoho', jsonb_build_object('state', v_zst, 'note', v_znote),
        'http', jsonb_build_object('state', 'not_checked', 'note', 'The database cannot call the website. The release check reads the Website API over HTTP; until it has, this is not checked, neither passed nor failed.')));
    end loop;
    return jsonb_build_object('verified_at', now(), 'courses', v_rows, 'missing', to_jsonb(array(select x from unnest(v_ids) x where x not in (select (e->>'course_id')::uuid from jsonb_array_elements(v_rows) e))),
      'summary', jsonb_build_object(
        'website', (select coalesce(jsonb_object_agg(s, n), '{}'::jsonb) from (select e->'website'->>'state' s, count(*) n from jsonb_array_elements(v_rows) e group by 1) z),
        'zoho', (select coalesce(jsonb_object_agg(s, n), '{}'::jsonb) from (select e->'zoho'->>'state' s, count(*) n from jsonb_array_elements(v_rows) e group by 1) z)));
  end if;

  if p_action = 'description_tasks' then
    if coalesce(p_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
    -- the saved record of the on-demand tasks (newest first; one screen's list), so the person finds the task and its outcome after closing the browser; optionally only the tasks that held one course
    return jsonb_build_object('tasks', coalesce((select jsonb_agg(t.x order by t.created_at desc) from (
      select j.created_at, jsonb_build_object('id', j.id, 'title', j.title, 'state', j.state, 'progress', j.progress, 'reason', j.reason, 'created_at', j.created_at, 'finished_at', j.finished_at,
               'mode', j.args->>'mode', 'scope', j.args->>'scope', 'requested_by', j.requested_by,
               'by_state', (select coalesce(jsonb_object_agg(z.s, z.n), '{}'::jsonb) from (select e.state s, count(*) n from pipeline.field_enrich_items e where e.job_id = j.id group by 1) z),
               'described_now', (select count(*) from pipeline.field_enrich_items e join catalogue.courses c on c.id = e.course_id where e.job_id = j.id and nullif(btrim(c.description), '') is not null)) x
        from pipeline.admin_jobs j
       where j.kind = 'enrich_fields' and j.args->>'on_demand' = 'true'
         and (cardinality(v_ids) = 0 or exists (select 1 from pipeline.field_enrich_items e where e.job_id = j.id and e.course_id = any (v_ids)))
       order by j.created_at desc limit 10) t), '[]'::jsonb)); -- fixed: one screen's list of tasks
  end if;

  -- preview and start
  if p_action not in ('preview', 'start') then raise exception 'unknown action %', p_action using errcode = '22023'; end if;
  if v_mode not in ('fill', 'recheck') then raise exception 'choose Fill description or Recheck description'; end if;
  if cardinality(v_ids) > 0 and cardinality(v_pids) > 0 then raise exception 'choose courses or one university, not both'; end if;
  if cardinality(v_ids) > 0 then
    v_scope := 'courses';
    if cardinality(v_ids) > v_max then raise exception 'choose at most % courses at a time (Pipeline settings > Run now: most courses in a cohort)', v_max; end if;
  elsif cardinality(v_pids) = 1 then
    v_scope := 'university';
  else
    raise exception 'choose up to % courses, or one university', v_max;
  end if;

  if p_action = 'start' then
    if coalesce(p_rank, 0) < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    v_reason := btrim(coalesce(a->>'reason', ''));
    if length(v_reason) < 4 then raise exception 'give a reason (it is kept with the task)'; end if;
    v_given := nullif(btrim(coalesce(a->>'idempotency_key', '')), '') is not null;
    v_key := left(coalesce(nullif(btrim(coalesce(a->>'idempotency_key', '')), ''),
                'cdesc:' || v_mode || ':' || md5(coalesce((select string_agg(x::text, ',' order by x) from unnest(case when v_scope = 'courses' then v_ids else v_pids end) x), ''))), 120); -- fixed: a key's length
    -- Locks come BEFORE the selection, so what is chosen is what is true when the items are written. A request for one university takes that university's lock exclusively; a request for chosen
    -- courses takes each course's lock exclusively and each of their universities' locks shared (so two course requests in one university run side by side, but a university request waits for
    -- them and they wait for it). Always taken providers first, then courses, in sorted order, so two requests can never wait on each other. The standing queue takes no lock: see the header.
    perform pg_advisory_xact_lock(hashtextextended('cdesc_on_demand:' || v_key, 0));
    if v_scope = 'university' then
      perform pg_advisory_xact_lock(hashtextextended('cdesc_provider:' || v_pids[1]::text, 0));
    else
      for r in select distinct co.provider_id pid from catalogue.courses co where co.id = any (v_ids) order by 1 loop
        perform pg_advisory_xact_lock_shared(hashtextextended('cdesc_provider:' || r.pid::text, 0));
      end loop;
      for r in select x from unnest(v_ids) x order by 1 loop
        perform pg_advisory_xact_lock(hashtextextended('cdesc_course:' || r.x::text, 0));
      end loop;
    end if;
    select * into v_ex from pipeline.admin_jobs j where j.kind = 'enrich_fields' and j.args->>'idempotency_key' = v_key and (v_given or j.state in ('queued', 'running')) order by j.created_at desc limit 1;
    if v_ex.id is not null then
      if v_ex.args->>'mode' is distinct from v_mode or v_ex.args->>'scope' is distinct from v_scope then
        raise exception 'this idempotency key was already used for a different request (% / %); use a new key', v_ex.args->>'mode', v_ex.args->>'scope';
      end if;
      return jsonb_build_object('job_id', v_ex.id, 'items', (select count(*) from pipeline.field_enrich_items e where e.job_id = v_ex.id), 'repeat', true, 'mode', v_mode, 'scope', v_scope, 'idempotency_key', v_key);
    end if;
  end if;

  -- the day's room under the standing queue's own ceiling (items already made today for the description, by any route)
  select v_cap - count(*) into v_used from pipeline.field_enrich_items e where e.field = 'description' and e.created_at > now() - interval '1 day'; -- fixed: the cap is a day's
  v_room := greatest(v_used, 0); -- v_used is what is left of the day's ceiling
  v_limit := case when v_scope = 'courses' then least(v_max, v_room) else v_room end; -- an on-demand request never takes more readings than the day's ceiling leaves

  create temporary table if not exists pg_temp.cdesc_sel (course_id uuid, provider_id uuid, block text, ord int, flags bigint[], payload jsonb) on commit drop;
  truncate pg_temp.cdesc_sel;
  insert into pg_temp.cdesc_sel(course_id, provider_id, block, ord, flags, payload)
  select s.course_id, s.provider_id, case v_mode when 'fill' then s.fill_block else s.recheck_block end,
         row_number() over (order by (s.last_item_id is not null), s.last_attempt_at nulls first, s.course_id),
         s.release_flag_ids,
         to_jsonb(s) || jsonb_build_object('fill_info', security.cdesc_block_info_v1(s.fill_block), 'recheck_info', security.cdesc_block_info_v1(s.recheck_block))
    from security.cdesc_state_v1(case when v_scope = 'courses' then v_ids end, case when v_scope = 'university' then v_pids[1] end) s;

  v_total := (select count(*) from pg_temp.cdesc_sel);
  -- back-pressure as the standing queue has it (enrich.course_description_pending_global_max, 0 = off): no new readings while that many descriptions already wait for a person in Layer 4
  if coalesce(security.pipeline_num_v1('enrich.course_description_pending_global_max', 0), 0) > 0
     and (select count(*) from pipeline.layer4_review_items q where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending')
         >= security.pipeline_num_v1('enrich.course_description_pending_global_max', 0) then
    update pg_temp.cdesc_sel set block = 'review_backlog' where block is null;
  end if;
  v_elig := (select count(*) from pg_temp.cdesc_sel where block is null);
  v_missing := array(select x from unnest(v_ids) x where x not in (select course_id from pg_temp.cdesc_sel));
  -- a request queues the first v_limit eligible courses (never-tried first, then the oldest attempt); the rest wait for the next request
  update pg_temp.cdesc_sel set block = 'daily_capacity' where block is null and ord > 0
     and (select count(*) from pg_temp.cdesc_sel x where x.block is null and x.ord <= pg_temp.cdesc_sel.ord) > v_limit;
  v_blocks := (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select block k, count(*) n from pg_temp.cdesc_sel where block is not null group by 1) z);
  v_n := (select count(*) from pg_temp.cdesc_sel where block is null);
  v_usd := nullif((security.enrich_unit_costs_v1()->>'enrich_usd_per_item')::numeric, 0);

  if p_action = 'preview' then
    if coalesce(p_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
    return jsonb_build_object('mode', v_mode, 'scope', v_scope, 'selected', case when v_scope = 'courses' then cardinality(v_ids) end, 'missing', to_jsonb(v_missing),
      'total', v_total, 'eligible', v_elig, 'to_queue', v_n, 'left_for_later', v_elig - v_n, 'blocked', v_blocks,
      'blocked_info', (select coalesce(jsonb_object_agg(k, security.cdesc_block_info_v1(k)), '{}'::jsonb) from jsonb_object_keys(v_blocks) k),
      'limit', jsonb_build_object('courses_per_request', v_max, 'room_today', v_room, 'items_per_day', v_cap),
      'estimate', jsonb_build_object('items', v_n, 'usd_per_item', v_usd, 'usd', case when v_usd is null then null else round(v_n * v_usd, 4) end, 'scraper_credits', 0),
      'courses', case when v_scope = 'courses' then (select coalesce(jsonb_agg(z.payload || jsonb_build_object('block', z.block, 'block_info', security.cdesc_block_info_v1(z.block), 'will_queue', z.block is null) order by z.ord), '[]'::jsonb) from pg_temp.cdesc_sel z)
                     else (select coalesce(jsonb_agg(z.payload || jsonb_build_object('block', z.block, 'block_info', security.cdesc_block_info_v1(z.block), 'will_queue', z.block is null) order by z.ord), '[]'::jsonb)
                             from (select * from pg_temp.cdesc_sel order by (block is not null), ord limit v_max) z) end);
  end if;

  -- start (rank, reason, key, locks and the repeat check were done before the selection)
  if v_n = 0 then
    raise exception 'nothing to queue: %', coalesce((select string_agg(coalesce(security.cdesc_block_info_v1(k)->>'label', k) || ' (' || n || ')', '; ' order by n desc) from (select block k, count(*) n from pg_temp.cdesc_sel where block is not null group by 1) z), 'no course found');
  end if;
  v_sel := array(select course_id from pg_temp.cdesc_sel where block is null order by ord);
  v_providers := array(select distinct provider_id from pg_temp.cdesc_sel where block is null);
  v_ptitle := case when v_scope = 'university' then (select coalesce(pr.display_name, pr.canonical_name) from catalogue.providers pr where pr.id = v_pids[1]) end;
  v_title := left((case v_mode when 'fill' then 'Fill description' else 'Recheck description' end) || ' · ' || case when v_scope = 'university' then coalesce(v_ptitle, 'university') || ' · ' || v_n || ' course(s)'
                                                                                                                     else v_n || ' course(s)' end, 200); -- fixed: the title column's length (as Enrich fields)
  insert into pipeline.admin_jobs(kind, lane, state, title, args, progress, requested_by, reason, scope)
  values ('enrich_fields', 'enrich', 'queued', v_title,
          jsonb_build_object('countries', '[]'::jsonb, 'provider_ids', to_jsonb(v_providers), 'fields', jsonb_build_array('description'), 'ai', true, 'scraper', false,
                             'on_demand', true, 'mode', v_mode, 'scope', v_scope, 'course_ids', case when v_scope = 'courses' then to_jsonb(v_sel) else '[]'::jsonb end,
                             'idempotency_key', v_key, 'requested_courses', case when v_scope = 'courses' then cardinality(v_ids) else v_total end),
          jsonb_build_object('done', 0, 'total', 0), p_uid, v_reason, case when v_scope = 'university' then coalesce(v_ptitle, '1 university') else v_n || ' courses' end)
  returning id into v_job;
  -- recheck: the counting flag (the standing queue's wait) of each chosen course's description is released as a person's release, in the flag history, so the engine's own gate lets the item in
  if v_mode = 'recheck' then
    for f in select unnest(flags) from pg_temp.cdesc_sel where block is null and flags is not null loop
      perform security.flag_release_v1(f, p_uid::text, 'person', 'Recheck description requested: ' || v_reason, jsonb_build_object('job_id', v_job), false);
    end loop;
  end if;
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field)
  select v_job, s.provider_id, s.course_id, 'description' from pg_temp.cdesc_sel s where s.block is null order by s.ord on conflict do nothing;
  select count(*) into v_n from pipeline.field_enrich_items where job_id = v_job;
  if v_n = 0 then raise exception 'nothing was queued (the engine''s own gate holds every chosen course); nothing was changed'; end if;
  update pipeline.admin_jobs set progress = jsonb_build_object('done', 0, 'total', v_n) where id = v_job;
  insert into pipeline.admin_job_events(job_id, note, detail) values (v_job, v_n || ' item(s) to settle', jsonb_build_object('mode', v_mode, 'scope', v_scope, 'reason', v_reason));
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('enrich_fields', 'on_demand_' || v_mode, v_job::text, jsonb_build_object('job_id', v_job, 'items', v_n, 'scope', v_scope, 'reason', v_reason, 'blocked', v_blocks, 'idempotency_key', v_key), p_uid);
  return jsonb_build_object('job_id', v_job, 'items', v_n, 'repeat', false, 'mode', v_mode, 'scope', v_scope, 'blocked', v_blocks, 'left_for_later', v_elig - v_n, 'idempotency_key', v_key);
end $function$;

-- 5. the read-only state for the screens --------------------------------------------------------------------------------------------------------------------------
create or replace function public.admin_course_description_state_v1(p_course_ids uuid[]) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v_cap int := 200; -- fixed: one screen page of rows (the Course Catalogue page size is the setting; this only bounds a hand-made call)
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_course_ids is null or cardinality(p_course_ids) = 0 then return jsonb_build_object('courses', '[]'::jsonb); end if;
  if cardinality(p_course_ids) > v_cap then raise exception 'ask for at most % courses at a time', v_cap; end if;
  return jsonb_build_object('read_at', now(), 'machine_ledger', security.cdesc_machine_ids_v1(p_course_ids) is not null,
    'recheck_days', security.pipeline_num_v1('gaps.recheck_days', 60)::int, 'courses_per_request', security.pipeline_num_v1('run_now.pilot_cap', 20)::int,
    'courses', (select coalesce(jsonb_agg(to_jsonb(s) || jsonb_build_object('fill_info', security.cdesc_block_info_v1(s.fill_block), 'recheck_info', security.cdesc_block_info_v1(s.recheck_block)) order by s.title, s.course_id), '[]'::jsonb)
                  from security.cdesc_state_v1(p_course_ids, null) s));
end $function$;

-- 6. grants, purposes, the existing settings' used_by, the register -------------------------------------------------------------------------------------------------
revoke all on function security.cdesc_machine_ids_v1(uuid[]) from public, anon, authenticated;
revoke all on function security.cdesc_block_info_v1(text) from public, anon, authenticated;
revoke all on function security.cdesc_state_v1(uuid[], uuid) from public, anon, authenticated;
revoke all on function security.cdesc_on_demand_v1(text, jsonb, int, uuid) from public, anon, authenticated;
revoke all on function public.admin_course_description_state_v1(uuid[]) from public, anon;
grant execute on function public.admin_course_description_state_v1(uuid[]) to authenticated, service_role;
comment on function security.cdesc_state_v1(uuid[], uuid) is 'CF-247 F-CDESC.06: where each course''s description stands (page, last Enrich fields item, flags, locks, Layer 4, machine ledger) and why Fill and Recheck would leave it out. Read only.';
comment on function security.cdesc_on_demand_v1(text, jsonb, int, uuid) is 'CF-247 F-CDESC.06: preview, start and verify of Fill description / Recheck description through the Enrich fields task engine (called by public.admin_enrich_fields).';
comment on function public.admin_course_description_state_v1(uuid[]) is 'CF-247 F-CDESC.06: read-only description pipeline state of the given courses (rank 3 and above).';

update pipeline.platform_toolset_settings set used_by = used_by || '; security.cdesc_on_demand_v1 (most courses of a Fill / Recheck description request)'
 where toolset_key = 'pipeline' and key = 'run_now.pilot_cap' and used_by not like '%cdesc_on_demand_v1%';
update pipeline.platform_toolset_settings set used_by = used_by || '; security.cdesc_on_demand_v1 (the day''s room for a university''s Fill / Recheck description request)'
 where toolset_key = 'pipeline' and key = 'enrich.course_text_items_per_day' and used_by not like '%cdesc_on_demand_v1%';
update pipeline.platform_toolset_settings set used_by = used_by || '; security.cdesc_on_demand_v1 (back-pressure for Fill / Recheck description)'
 where toolset_key = 'pipeline' and key = 'enrich.course_description_pending_global_max' and used_by not like '%cdesc_on_demand_v1%';

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.cdesc_state_v1', 'Platform', 'Course descriptions', 'Fill / Recheck description on demand: where each course''s description stands and why it would be left out (read only)', 'active', '{}', '20261110070000'),
 ('function', 'security.cdesc_on_demand_v1', 'Platform', 'Course descriptions', 'Fill / Recheck description on demand: preview, start (an ordinary Enrich fields task) and verify (read back of the catalogue, Website and Zoho feeds)', 'active', '{}', '20261110070000'),
 ('function', 'security.cdesc_block_info_v1', 'Platform', 'Course descriptions', 'Fill / Recheck description on demand: plain-words reason and next action for each reason a course is left out', 'active', '{}', '20261110070000'),
 ('function', 'security.cdesc_machine_ids_v1', 'Platform', 'Course descriptions', 'Fill / Recheck description on demand: which courses the machine-admission ledger holds (unknown while the ledger does not exist)', 'active', '{}', '20261110070000'),
 ('function', 'public.admin_course_description_state_v1', 'Platform', 'Course descriptions', 'Fill / Recheck description on demand: read-only per-course description state for the Course Catalogue, Course Detail and Provider Catalogue', 'active', '{}', '20261110070000')
on conflict do nothing;

-- 7. the one edit of public.admin_enrich_fields (md5-guarded) ------------------------------------------------------------------------------------------------------------
create or replace function pg_temp.edit_one(p_sig text, p_before text, p_after text, p_old text, p_new text, p_final text) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after or md5(v_src) = p_final then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(v_def, chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_one('public.admin_enrich_fields(text,jsonb)', 'c9701d334b732a729a30a5147d9d016b', 'f11db4466add68c4d7de5cb7c87d9bce',
$old$  if p_action = 'fields' then
$old$,
$new$  -- CF-247 F-CDESC.06 (Platform Admin 10 Nov 2026): Fill description / Recheck description for chosen courses or one university, and the read-back of what they delivered, run through this same task engine
  if p_action in ('verify', 'description_tasks') or (p_action in ('preview', 'start') and (p_args ? 'course_ids' or p_args ? 'mode')) then
    return security.cdesc_on_demand_v1(p_action, p_args, v_rank, auth.uid());
  end if;
  if p_action = 'fields' then
$new$, 'f11db4466add68c4d7de5cb7c87d9bce');

do $post$
begin
  if position('security.cdesc_on_demand_v1' in pg_get_functiondef('public.admin_enrich_fields(text,jsonb)'::regprocedure)) = 0 then
    raise exception 'cdesc on demand post-check: public.admin_enrich_fields does not dispatch to security.cdesc_on_demand_v1';
  end if;
  if position('elsif p_action = ''retry''' in pg_get_functiondef('public.admin_enrich_fields(text,jsonb)'::regprocedure)) = 0 then
    raise exception 'cdesc on demand post-check: the retry action of public.admin_enrich_fields is missing';
  end if;
end $post$;
