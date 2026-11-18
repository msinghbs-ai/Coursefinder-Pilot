-- CF-247 AER "Read / refresh entry requirements now" (Platform Admin decision 10 Nov 2026 19:47: the one-primary-outcome-action experience of the shared source-to-published design, applied to academic entry requirements;
--   admin docs/platform/SHARED-SOURCE-TO-PUBLISHED-ENRICHMENT-DESIGN.md sections 2, 3, 4.3, 5, 7, 8 and STUDYSEARCH-FEATURE-ACCEPTANCE.md F-AER.01-.06).
-- Guards: G1 (no job added: the on-demand work shares the queues and jobs that already exist), G2 (no operational value in code: every limit is an existing setting; the only constants are technical and marked `-- fixed:`),
--   G3 (no consumer API object, table or column is read for its shape or changed), Decision 260 (housekeeping), "a passing qualification never switches anything on by itself" (no setting, switch or job state is changed),
--   F-AER.04 (first reads and protected changes stay human Layer 4 decisions: nothing here approves, admits, activates or publishes a row).
-- Replaces: security.aer_course_population_v1() (md5-guarded: it now delegates to the new provider-scoped form, the eligibility rules are written once), security.data_delivery_aer_v1() (md5-guarded: one additive key `reviewer`),
--   security.layer4_aer_review_detail_v1(text) (md5-guarded: one added section `facts`), security.data_delivery_v1() (anchored edit, applied once to whatever is live: the recovery state is `off` only when EVERY switch of the lane is off, and the
--   switches that are off are named); the edits are taken back by supabase/held/aer_read_now_forward_recovery.sql
-- Retires: nothing (the existing per-course "Read from the stored page", per-source "Read again" and "Read next batch" controls and their functions are kept as the advanced controls; this adds the one primary action above them)
--
-- Evidence (production, read only, 10 Nov 2026 AEDT, project fxcwkweaxjtknorudmwp):
--   * Stage facts that exist today: entry_matrix_sources (source found, 1 row a page), entry_matrix_runs and the proposed rows (AI parsed candidates), pipeline.layer4_item_readiness (stored completeness gate: 250 of 665 pending AER items are
--     judgement_ready = a complete reviewer packet; 415 are technical_blocked by the completeness gate), pipeline.layer4_review_items (awaiting a person), the active rows (1,304 course, 663 matrix) and the decided counts.
--     No table records the stage of a REQUEST: the existing pipeline.admin_control_events holds it (area aer_read_now), the work itself is in the existing queues; no table is added.
--   * Providers by stage: 1,415 eligible providers have no source (373 nothing stored, 168 course pages matched by title only awaiting a Platform Admin decision, 875 stored and bound course pages the free route can read, 7 a stored entry page, 1 a shared
--     host, 3 a weak page); 33 have a source with a complete or incomplete packet. Job aer-source-stored-find first run: 400 providers checked, 383 no entry candidate, 10 attached (16 sources), 6 no link material, 1 shared host.
--   * Waiting reviewer packets: 618 course_entry_first_read and 47 entry_matrix_first_run pending; of their 4,776 proposed rows, 1,946 of 2,242 matrix rows print no intake year or edition, 326 course rows print a grade without a scale, 372 matrix
--     rows print no minimum. The stored gate checks page completeness, not these facts; the reviewer packet never named them. They are flagged here as "not stated" and are never filled in.
--   * Data Delivery shows the aer stream recovery as "off" while job aer-scheduled-read is active and ran within the hour: security.data_delivery_v1 marks a stream off when ANY switch of its lane is off (bool_or), and the lane lists
--     aer.replay_on = 1, aer.source_stored_find_on = 1 and aer.e13_recover_on = 0 (the E13 pilot, deliberately off). Stream sch (3 of 4 switches off) shows off for the same reason. A display defect in the owning derivation, fixed below.
--   * security.course_entry_eligible_v1()/aer_course_population_v1() take 5.3 s for one provider and 13 s for all (the provider predicate cannot reach the ranking CTE); the same rules restricted inside the first CTE take 106 ms. The on-demand
--     action needs the provider-scoped form to stay inside the 8 s statement limit of a signed-in call.
-- What this changes:
--   1. security.aer_course_population_v1(uuid) NEW: the eligibility rules of the scheduled reading, restricted to one provider (null = all). The no-argument form delegates to it, so the rules are written once.
--   2. security.aer_packet_rows_v1(uuid) NEW (read only): for each proposed row of a waiting entry item, whether country, qualification, grade, scale, applicability, source page and year are STATED, NOT STATED, NOT APPLICABLE or NOT RECORDED.
--      security.aer_packet_facts_v1(uuid) NEW: the same for one item, as a reviewer section. A fact that is not printed is flagged, never filled in or inferred; an as-at date is the capture date, not a printed year.
--   3. security.aer_pending_packets_v1(uuid, uuid) NEW (read only): the waiting entry items of a provider or a course with their packet state: reviewer_ready (the stored gate is complete), technical_hold, needs_input (parked), not_checked.
--   4. security.aer_read_now_plan_v1(uuid, uuid) NEW (read only): what one click would do, or why it would do nothing, as one outcome: queued, in_progress, human_review_required, already_up_to_date, no_eligible_work,
--      source_unavailable, switch_off, budget_reached (permission_denied is answered by the public wrapper). It reuses, in this order: the stored copy of the page (no fetch), a read again of a source that failed technically, the replay of a held read
--      from stored records, and the first reads of courses whose bound page is already stored (security.course_entry_read_enqueue_v1, the scheduled reader's own function). No Firecrawl call, no page search and no E13 AI re-read is started.
--   5. security.aer_read_now_status_v1(uuid, uuid) NEW (read only): the stage timeline (source found, AI parsed candidates, complete reviewer packet, awaiting a person, approved and active, consumer visible) with counts, plus the plan.
--   6. security.aer_read_now_v1(uuid, uuid, text, uuid) NEW: runs the plan once (one advisory lock a scope, so a second click is a no-op while work is in flight) and records one pipeline.admin_control_events row (area aer_read_now).
--   7. public.admin_aer_read_now(jsonb) NEW: the signed-in wrapper (action status: any assigned role; action run: Platform Admin, rank 6, as the existing per-course read and per-source read again).
--   8. security.data_delivery_aer_v1 (additive key reviewer): reviewer-ready packets against active approved rows, by kind, with the facts flagged, the decisions to date and the on-demand requests; security.layer4_aer_review_detail_v1 (section facts).
--   9. security.data_delivery_v1 (anchored): recovery state off only when every switch is off; the switches that are off are named (additive key switches_off).
--      THE DISPLAYED STATE CHANGES FOR MORE THAN AER: the rule is in the shared derivation, so it changes the displayed recovery state of the aer AND the sch streams (and any other stream whose lane lists several switches): a stream
--      that showed "Off" because one of several routes is off now shows its real state and names the route that is off. Nothing is switched on or off; only what the screen says changes. (The Data Delivery screen file is not changed here.)
--  10. Operating Model v1.7 (evidence-backed absence), scope delta 10 Nov 2026: the plan and status name what the evidence says, from existing state and reason only (no new state, enum or table): security.aer_read_now_class_v1(text, text) NEW
--      (a screen label: no_source_on_record, source_found_not_read, tried_not_found, technical_failure, budget_hold, human_review) and security.aer_read_now_source_v1(uuid, uuid) NEW (the source examined: url, status, read time, stored copy, hash, last
--      result as recorded). "Read, nothing kept" (reason tried_not_found) is said only where a stored result says it; unchanged evidence (same stored copy, or the same content hash) is not read again; a budget or switch refusal happens in the plan,
--      before any reader is called, so it creates no job or item and uses none of a reader's attempts. First reads stay human Layer 4 decisions.
--      A read the READER HELD (held_unparsed, held_incomplete, held: ...) is never an absence: it is human_review_required, reason reader_held, no green chip, and it is not queued again against an unchanged page.
--      A failed read (source or course) asked for from here is not queued again against the same content hash before the retry interval (aer.schedule_retry_days): the request and the hash are in the event (admin_control_events).
--      Source reads again and replays asked from here count with course reads against the shared daily allowance. "No source on record" means nothing recorded a source or a discovery attempt; it is not a finding that discovery ran.
-- No setting, schedule, ledger, finding or data row is changed by this migration; no job is added; nothing is fetched, read by AI, admitted or published. Nothing is dropped or deleted.
-- Live definitions this change edits (pg_proc.prosrc md5, read 10 Nov 2026), before -> after:
--   security.aer_course_population_v1() d593eb0aa0fe06b0b4b28c86821bfff5 -> 39df48e65bc7f0d4c3dcb4cde5d244cc
--   security.data_delivery_aer_v1() 27a42c5f02d09f518e77bd965814bbe0 -> f66f692580977dcef97f8db5b01b3403
--   security.layer4_aer_review_detail_v1(text) 330e079018c93f8db8a649ed3a08ae12 -> e377494a017ea32e2b5d50f7b87c733c
--   security.data_delivery_v1() 208067f054c2f3ac7adb1196e3e8c25c -> 74ead0d5a3b7b4e48d4783f25c350865
-- The three md5-guarded edits stop (and nothing is applied) when the live body is neither the one they replace nor the one they write. The Data Delivery edit is anchored text applied once to whatever the live body is.

do $g$
declare r record;
begin
  for r in select * from (values ('security.aer_course_population_v1()'), ('security.data_delivery_aer_v1()'), ('security.layer4_aer_review_detail_v1(text)'), ('security.data_delivery_v1()'),
                                 ('security.pipeline_num_v1(text,numeric)'), ('security.toolset_setting(text,text)'), ('security.aer_eligible_v1()'), ('security.aer_schedule_country_v1(text)'),
                                 ('security.aer_review_kinds_v1()'), ('security.aer_parked_items_v1()'), ('security.ai_use_refusal_v1(text)'), ('security.course_entry_cost_v1()'),
                                 ('security.course_entry_read_enqueue_v1(uuid,uuid,text)'), ('security.aer_reread_v1(uuid,text,uuid)'), ('security.aer_replay_plan_v1(uuid)'), ('security.aer_replay_apply_v1(uuid,jsonb)'),
                                 ('security.entry_matrix_enabled_v1(uuid)'), ('security.coverage_identity_allowed(uuid,text,text)'), ('security.current_role_rank()'), ('security.cron_next_run_v1(text,timestamp with time zone)'),
                                 ('security.provider_hidden_v1')) v(sig) loop
    if to_regprocedure(r.sig) is null and to_regclass(replace(split_part(r.sig, '(', 1), '()', '')) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  if to_regclass('pipeline.layer4_item_readiness') is null or to_regclass('pipeline.admin_control_events') is null or to_regclass('pipeline.entry_matrix_sources') is null or to_regclass('pipeline.entry_matrix_runs') is null
     or to_regclass('pipeline.field_enrich_items') is null or to_regclass('pipeline.aer_gap_findings') is null or to_regclass('pipeline.aer_source_stored_find') is null or to_regclass('pipeline.aer_schedule_runs') is null
     or to_regclass('pipeline.aer_replay_checks') is null or to_regclass('pipeline.aer_read_supersessions') is null or to_regclass('catalogue.provider_entry_matrix') is null
     or to_regclass('catalogue.course_entry_requirements') is null or to_regclass('pipeline.coverage_course_pages') is null then
    raise exception 'a table this change reads is missing';
  end if;
end $g$;

-- 1. the provider-scoped eligibility rules ----------------------------------------------------------------------------------------------------
-- The same rules as the no-argument form had (copied unchanged), with the provider restriction applied inside the first CTE so that it reaches the join order. Called with null it is the whole population as before.
create or replace function security.aer_course_population_v1(p_provider uuid)
returns table(course_id uuid, provider_id uuid, country text, provider_name text, tier integer, prio bigint, title text)
language sql stable security definer set search_path = ''
as $f$
  with s as (select coalesce(security.toolset_setting('pipeline', 'aer.schedule_lock_fields'), '[]'::jsonb) locks,
                    coalesce(security.toolset_setting('pipeline', 'aer.priority_provider_types'), '[]'::jsonb) pt,
                    -- CF-247 workstream C (Integration Controller 3 Nov 2026 18:30): followed providers, then the largest AER shortfall, first
                    coalesce((security.toolset_setting('pipeline', 'coverage.aer_reader_priority_on') #>> '{}')::boolean, false) gap_first,
                    coalesce(security.toolset_setting('pipeline', 'coverage.aer_priority_providers'), '[]'::jsonb) followed),
  pv as (select e.provider_id, e.country, coalesce(p.display_name, p.short_name, p.canonical_name) pname,
                case when s.gap_first and s.followed ? e.provider_id::text then -1000000
                     when s.gap_first and coalesce(k.shortfall, 0) > 0 then -least(k.shortfall, 999999)
                     when s.pt ? coalesce(t.code, '') then 1 else 2 end tier
           from security.aer_eligible_v1() e
           join catalogue.providers p on p.id = e.provider_id
           left join ref.provider_types t on t.id = p.provider_type_id
           left join pipeline.coverage_provider_reconciliation k on k.domain = 'aer' and k.provider_id = e.provider_id
          cross join s
          where (p_provider is null or e.provider_id = p_provider)
            and (security.aer_schedule_country_v1(e.country)->>'on')::boolean
            and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = e.provider_id)),
  pr as (select pv.*, dense_rank() over (order by pv.tier, pv.pname, pv.provider_id) prio from pv)
  select c.id, pr.provider_id, pr.country, pr.pname, pr.tier, pr.prio, c.canonical_title
    from pr
    join catalogue.courses c on c.provider_id = pr.provider_id and c.lifecycle_status = 'active'
    join pipeline.coverage_course_pages g on g.course_id = c.id and g.status = 'bound'
    join pipeline.evidence_artifacts a on a.id = g.evidence_id and a.storage_path is not null
   cross join s
   where security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements')
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and (s.locks ? l.field or l.field = 'all'))
$f$;
revoke all on function security.aer_course_population_v1(uuid) from public, anon, authenticated;
comment on function security.aer_course_population_v1(uuid) is 'CF-247 AER read now (10 Nov 2026): the eligibility rules of the scheduled entry reading (security.aer_course_population_v1()) for one provider, or all providers when null. The no-argument form delegates here, so the rules are written once. Read only.';

-- 2. packet facts ---------------------------------------------------------------------------------------------------------------------------
-- One row for every proposed row of a waiting entry item. Each fact is one of: stated, not_stated, not_applicable, not_recorded. Nothing is inferred: an empty value is "not stated", whatever the other rows or another country say.
create or replace function security.aer_packet_rows_v1(p_item uuid default null)
returns table(item_id uuid, field_code text, provider_id uuid, course_id uuid, row_id uuid, track text, country text, qualification text, grade text, scale text, applicability text, source_page text, year text)
language sql stable security definer set search_path = ''
as $f$
  select i.id, i.field_code, i.entity_id, null::uuid, m.id, 'matrix'::text,
         case when nullif(btrim(m.country_code), '') is not null then 'stated' else 'not_stated' end,
         case when nullif(btrim(m.qualification_name), '') is not null then 'stated' else 'not_stated' end,
         case when nullif(btrim(m.min_grade), '') is not null or m.min_value is not null then 'stated' else 'not_stated' end,
         case when nullif(btrim(m.min_grade), '') is null and m.min_value is null then 'not_applicable' when nullif(btrim(m.grade_scale), '') is not null then 'stated' else 'not_stated' end,
         case when (nullif(btrim(m.level_label), '') is not null or m.study_level_id is not null or m.aer_level is not null) and nullif(btrim(m.audience), '') is not null then 'stated' else 'not_stated' end,
         case when nullif(btrim(m.source_url), '') is not null and nullif(btrim(m.quote), '') is not null and m.evidence_id is not null then 'stated' else 'not_stated' end,
         -- the printed year or edition only; as_at is the date the page was read, never a year the page states
         case when m.intake_year is not null or nullif(btrim(m.edition), '') is not null then 'stated' else 'not_stated' end
    from pipeline.layer4_review_items i
    join pipeline.entry_matrix_runs r on r.review_item_id = i.id
    join catalogue.provider_entry_matrix m on m.run_id = r.id and m.status = 'proposed'
   where i.status = 'pending' and i.field_code in ('entry_matrix_first_run', 'entry_matrix_change') and (p_item is null or i.id = p_item)
  union all
  select i.id, i.field_code, c.provider_id, i.entity_id, q.id, 'course'::text,
         -- a course row carries its audience, not a country of prior education: a country is stated only when the row has one, otherwise the fact does not apply (it is never taken from another row)
         case when q.country_id is not null then 'stated' else 'not_applicable' end,
         case when nullif(btrim(q.description), '') is not null then 'stated' else 'not_stated' end,
         case when nullif(btrim(q.min_grade), '') is not null or q.min_value is not null or q.min_entry_score is not null then 'stated'
              when q.kind = 'minimum_grade' then 'not_stated' else 'not_applicable' end,  -- fixed: only a minimum-grade row is expected to print a grade
         case when ((nullif(btrim(q.min_grade), '') is not null or q.min_value is not null) and nullif(btrim(q.grade_scale), '') is null)
                or (q.min_entry_score is not null and nullif(btrim(q.min_entry_score_basis), '') is null) then 'not_stated'
              when nullif(btrim(q.min_grade), '') is not null or q.min_value is not null or q.min_entry_score is not null then 'stated' else 'not_applicable' end,
         case when nullif(btrim(q.audience), '') is not null then 'stated' else 'not_stated' end,
         case when nullif(btrim(q.source_url), '') is not null and nullif(btrim(q.quote), '') is not null and q.evidence_id is not null then 'stated' else 'not_stated' end,
         'not_recorded'::text  -- the course row has no field for a printed intake year: it is said so, not guessed
    from pipeline.layer4_review_items i
    join catalogue.course_entry_requirements q on q.provenance->>'review_item_id' = i.id::text and q.status = 'proposed'
    join catalogue.courses c on c.id = i.entity_id
   where i.status = 'pending' and i.field_code = 'course_entry_first_read' and (p_item is null or i.id = p_item)
$f$;
revoke all on function security.aer_packet_rows_v1(uuid) from public, anon, authenticated;
comment on function security.aer_packet_rows_v1(uuid) is 'CF-247 AER read now (10 Nov 2026): for every proposed row of a waiting entry item (provider matrix or course read), whether country, qualification, grade, scale, applicability, source page and year are stated, not stated, not applicable or not recorded. Nothing is inferred or filled. Read only.';

create or replace function security.aer_packet_facts_v1(p_item uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $f$
declare v_rows int; v_complete int; v_flagged int; v_ns jsonb; v_nr jsonb; v_list jsonb; v_cap int := security.pipeline_num_v1('aer.review_packet_rows', 30)::int;
begin
  with x as (select r.*, array_remove(array[case when r.country = 'not_stated' then 'country' end, case when r.qualification = 'not_stated' then 'qualification' end, case when r.grade = 'not_stated' then 'grade' end,
                                            case when r.scale = 'not_stated' then 'scale' end, case when r.applicability = 'not_stated' then 'applicability' end,
                                            case when r.source_page = 'not_stated' then 'source page' end, case when r.year = 'not_stated' then 'year' end], null) miss
               from security.aer_packet_rows_v1(p_item) r)
  select count(*), count(*) filter (where cardinality(miss) = 0), count(*) filter (where cardinality(miss) > 0),
         jsonb_strip_nulls(jsonb_build_object('country', nullif(count(*) filter (where country = 'not_stated'), 0), 'qualification', nullif(count(*) filter (where qualification = 'not_stated'), 0),
              'grade', nullif(count(*) filter (where grade = 'not_stated'), 0), 'scale', nullif(count(*) filter (where scale = 'not_stated'), 0), 'applicability', nullif(count(*) filter (where applicability = 'not_stated'), 0),
              'source_page', nullif(count(*) filter (where source_page = 'not_stated'), 0), 'year', nullif(count(*) filter (where year = 'not_stated'), 0))),
         jsonb_strip_nulls(jsonb_build_object('year', nullif(count(*) filter (where year = 'not_recorded'), 0))),
         coalesce((select jsonb_agg(jsonb_build_object('row', z.row_id, 'not_stated', to_jsonb(z.miss)) order by z.row_id) from (select * from x where cardinality(miss) > 0 order by row_id limit v_cap) z), '[]'::jsonb)
    into v_rows, v_complete, v_flagged, v_ns, v_nr, v_list from x;
  return jsonb_build_object('item', p_item, 'rows', v_rows, 'complete_rows', v_complete, 'flagged_rows', v_flagged, 'not_stated', v_ns, 'not_recorded', v_nr, 'flagged', v_list,
    'section', jsonb_strip_nulls(jsonb_build_object(
       'Rows', v_rows, 'Rows with every fact stated', v_complete, 'Rows with a fact not stated', nullif(v_flagged, 0),
       'Facts not stated (rows)', nullif(v_ns, '{}'::jsonb), 'Facts the row cannot hold', nullif(v_nr, '{}'::jsonb),
       'Rows to check', nullif(v_list, '[]'::jsonb),
       'Note', 'A fact the page does not print is shown as not stated. It is never filled in, inferred from another row or country, or taken from the date the page was read.')));
end $f$;
revoke all on function security.aer_packet_facts_v1(uuid) from public, anon, authenticated;
comment on function security.aer_packet_facts_v1(uuid) is 'CF-247 AER read now (10 Nov 2026): the facts check of one waiting entry item for its reviewer: rows, rows with every fact stated, and how many rows leave country, qualification, grade, scale, applicability, source page or year not stated. Read only; nothing is filled in.';

-- 3. the waiting packets of a provider or a course -------------------------------------------------------------------------------------------
create or replace function security.aer_pending_packets_v1(p_provider uuid default null, p_course uuid default null)
returns table(item_id uuid, field_code text, provider_id uuid, course_id uuid, created_at timestamptz, readiness text, route text, reasons text[], gate_complete boolean, packet_state text, classified_at timestamptz, parked_reason text)
language sql stable security definer set search_path = ''
as $f$
  select z.id, z.field_code, z.pid, z.cid, z.created_at, z.readiness, z.route, z.reasons, z.complete,
         case when z.readiness = 'judgement_ready' then 'reviewer_ready'
              when z.parked_reason is not null then 'needs_input'
              when z.readiness is null then 'not_checked'
              else 'technical_hold' end,
         z.classified_at, z.parked_reason
    from (select i.id, i.field_code, coalesce(c.provider_id, case when i.entity_type = 'provider' then i.entity_id end) pid, case when i.entity_type = 'course' then i.entity_id end cid, i.created_at,
                 y.readiness, y.route, y.reasons, coalesce((y.gate->>'complete')::boolean, false) complete, y.classified_at, pk.reason parked_reason
            from pipeline.layer4_review_items i
            left join pipeline.layer4_item_readiness y on y.item_id = i.id
            left join catalogue.courses c on i.entity_type = 'course' and c.id = i.entity_id
            -- the technical lane's parked record of THIS item, by the unique key (lane, entity, work_kind): the rule of security.aer_parked_items_v1() without computing it for every item (that function costs seconds on its own)
            left join lateral (select w.unresolved_blocker->>'reason' reason from pipeline.work_items w
                                where w.lane = 'aer_technical' and w.work_kind = 'l4_item' and w.entity = i.id::text and w.stage = 'parked' and w.unresolved_blocker->>'action' = 'park'
                                  and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')) pk on true  -- fixed: the two entry-requirement item kinds the parked record covers
           where i.status = 'pending' and i.field_code = any (security.aer_review_kinds_v1())
             and (p_course is null or (i.entity_type = 'course' and i.entity_id = p_course))
             and (p_provider is null or coalesce(c.provider_id, case when i.entity_type = 'provider' then i.entity_id end) = p_provider)) z
$f$;
revoke all on function security.aer_pending_packets_v1(uuid, uuid) from public, anon, authenticated;
comment on function security.aer_pending_packets_v1(uuid, uuid) is 'CF-247 AER read now (10 Nov 2026): the waiting entry-requirement Layer 4 items of a provider or a course with their packet state from the stored completeness gate: reviewer_ready (a person can decide it now), technical_hold (the gate holds it; recovery applies), needs_input (parked by the technical lane), not_checked. Read only.';

-- 4. the plan -----------------------------------------------------------------------------------------------------------------------------
create or replace function security.aer_read_now_out_v1(p_outcome text, p_reason text, p_text text, p_next text, p_actions jsonb default '[]'::jsonb, p_extra jsonb default '{}'::jsonb)
returns jsonb language sql immutable set search_path = ''
as $f$ select jsonb_build_object('outcome', p_outcome, 'reason', p_reason, 'text', p_text, 'next_action', p_next, 'actions', coalesce(p_actions, '[]'::jsonb)) || coalesce(p_extra, '{}'::jsonb) $f$;
revoke all on function security.aer_read_now_out_v1(text, text, text, text, jsonb, jsonb) from public, anon, authenticated;

-- 3b. the kind of evidence an outcome rests on, and the source that was examined ------------------------------------------------------------------
-- Operating Model v1.7 (evidence-backed absence), scope delta 10 Nov 2026. No new state, enum or table: the kind is a label worked out from the outcome and reason the plan already gives, and the source is read from the records of the existing readers.
-- Absence is never inferred: "tried, not found" is said only when a stored read result says so; a field that no read recorded is not described as searched.
create or replace function security.aer_read_now_class_v1(p_outcome text, p_reason text)
returns text language sql immutable set search_path = ''
as $f$ select case
  when p_outcome = 'budget_reached' then 'budget_hold'
  when p_outcome = 'human_review_required' then 'human_review'
  when p_reason in ('nothing_stored', 'no_course_page') then 'no_source_on_record'
  when p_reason in ('course_page_not_bound', 'no_stored_copy', 'identity_not_admitted', 'host_shared', 'weak_page_only', 'stored_page_not_yet_attached', 'stored_find_off', 'robots_disallowed') then 'source_found_not_read'
  when p_reason = 'tried_not_found' then 'tried_not_found'
  when p_reason in ('technical_failure_retry', 'technical_failure_retried', 'source_fetch_failed') then 'technical_failure'
  end $f$;
revoke all on function security.aer_read_now_class_v1(text, text) from public, anon, authenticated;
comment on function security.aer_read_now_class_v1(text, text) is 'CF-247 AER read now (10 Nov 2026, Operating Model v1.7): the kind of evidence behind an outcome, as a screen label only (no_source_on_record, source_found_not_read, tried_not_found, technical_failure, budget_hold, human_review, or null). Derived from the existing outcome and reason; it is not stored and is not a state.';

create or replace function security.aer_read_now_source_v1(p_provider uuid, p_course uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $f$
declare g record; v_list jsonb; v_n int;
begin
  if p_course is not null then
    select pg.url, pg.status, pg.identity_basis, a.captured_at, left(a.content_hash, 12) hash, (a.storage_path is not null) stored into g
      from pipeline.coverage_course_pages pg left join pipeline.evidence_artifacts a on a.id = pg.evidence_id where pg.course_id = p_course;
    if g.url is null then return jsonb_build_object('kind', 'course_page', 'recorded', false); end if;
    return jsonb_build_object('kind', 'course_page', 'recorded', true, 'url', g.url, 'binding', g.status, 'matched_by', g.identity_basis, 'stored', g.stored, 'captured_at', g.captured_at, 'content_hash', g.hash,
      'last_read', (select jsonb_build_object('state', f.state, 'recorded_reason', left(f.reason, 200), 'at', f.updated_at) from pipeline.field_enrich_items f
                     where f.course_id = p_course and f.field = 'entry_requirements' and f.state in ('review', 'filled', 'skipped', 'failed') order by f.id desc limit 1));
  end if;
  select count(*) into v_n from pipeline.entry_matrix_sources s where s.provider_id = p_provider;
  select coalesce(jsonb_agg(x.j order by x.rk nulls last, x.id), '[]'::jsonb) into v_list from (
    select s.id, s.rank rk, jsonb_build_object('url', s.url, 'status', s.status, 'http_status', s.http_status, 'read_at', s.read_at, 'stored', ev.storage_path is not null, 'content_hash', left(s.content_hash, 12), 'error', left(s.error, 160),
             'last_run', (select jsonb_build_object('state', mr.state, 'rows_kept', mr.rows_admitted, 'error', left(mr.error, 160), 'at', coalesce(mr.done_at, mr.updated_at))
                            from pipeline.entry_matrix_runs mr where mr.source_id = s.id order by (mr.content_hash is not distinct from s.content_hash) desc, mr.created_at desc limit 1)) j
      from pipeline.entry_matrix_sources s left join pipeline.evidence_artifacts ev on ev.id = s.evidence_id where s.provider_id = p_provider) x;
  return jsonb_build_object('kind', 'matrix_sources', 'recorded', v_n > 0, 'count', v_n, 'sources', v_list);
end $f$;
revoke all on function security.aer_read_now_source_v1(uuid, uuid) from public, anon, authenticated;
comment on function security.aer_read_now_source_v1(uuid, uuid) is 'CF-247 AER read now (10 Nov 2026, Operating Model v1.7): the source that was examined, exactly as the existing readers recorded it. For a course: the bound page, its binding and match basis, the stored copy and its hash, and the last read result. For a provider: each entry source with its status, http status, read time, stored copy and last run (rows kept, error). Read only; nothing is inferred and a missing record is reported as not recorded.';

create or replace function security.aer_read_now_plan_v1(p_provider uuid, p_course uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $f$
declare
  v_pid uuid; v_cid uuid; v_pname text; v_ctitle text; v_cc text; v_life text;
  v_ai text := security.ai_use_refusal_v1('enrich_fields'); v_aim text := security.ai_use_refusal_v1('entry_matrix');
  v_bal numeric; v_floor numeric := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0); v_cost numeric := security.course_entry_cost_v1();
  v_per int := security.pipeline_num_v1('aer.schedule_per_provider', 5)::int; v_daymax int := security.pipeline_num_v1('aer.schedule_daily_max', 200)::int;
  v_l4max int := security.pipeline_num_v1('aer.schedule_layer4_max', 600)::int; v_srcmax int := security.pipeline_num_v1('entry.attach_per_provider', 3)::int;
  v_replay_on boolean := security.pipeline_num_v1('aer.replay_on', 1) >= 1; v_replay_per int := security.pipeline_num_v1('aer.replay_per_provider', 5)::int;
  v_replay_left int := security.pipeline_num_v1('aer.replay_daily_max', 100)::int - (select count(*) from pipeline.aer_read_supersessions s where s.reason like 'Replay of the stored read%' and s.requested_at > now() - interval '1 day');  -- fixed: the replay cap is counted over the last 24 hours, as the replay job counts it
  v_e13_on boolean := security.pipeline_num_v1('aer.e13_recover_on', 0) >= 1; v_sf_on boolean := security.pipeline_num_v1('aer.source_stored_find_on', 0) >= 1;
  v_used int; v_od int; v_l4 int; v_parked int; v_prog int; v_room int; v_n int; v_actions jsonb := '[]'::jsonb; v_blocks jsonb := '[]'::jsonb; v_extra jsonb;
  r record; g record; p jsonb; v_cnt jsonb; v_same boolean := false; v_sn record; v_hold_ids uuid[]; v_retry int := security.pipeline_num_v1('aer.schedule_retry_days', 30)::int; v_when timestamptz; v_inflight int; v_elig int; v_pick uuid[]; v_ready int; v_hold int; v_input int; v_chk int; v_srcs int; v_stale text; v_route text;
begin
  if p_course is not null then
    select c.id, c.provider_id, coalesce(c.display_title, c.canonical_title), c.lifecycle_status, k.iso_alpha2::text, coalesce(pv.display_name, pv.canonical_name)
      into v_cid, v_pid, v_ctitle, v_life, v_cc, v_pname
      from catalogue.courses c join catalogue.providers pv on pv.id = c.provider_id left join ref.countries k on k.id = pv.country_id where c.id = p_course;
  else
    select pv.id, coalesce(pv.display_name, pv.canonical_name), k.iso_alpha2::text into v_pid, v_pname, v_cc
      from catalogue.providers pv left join ref.countries k on k.id = pv.country_id where pv.id = p_provider;
  end if;
  if v_pid is null then return security.aer_read_now_out_v1('no_eligible_work', 'unknown_scope', 'That provider or course was not found.', null); end if;
  select o.remaining_usd into v_bal from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;

  ---------------------------------------------------------------------------------------------------------------------------------- one course
  if v_cid is not null then
    if v_life is distinct from 'active' then return security.aer_read_now_out_v1('no_eligible_work', 'course_not_active', 'The course is not active, so there is nothing to read.', null); end if;
    if v_cc is null or not coalesce(security.toolset_setting('pipeline', 'entry.course_read_countries'), '[]'::jsonb) ? v_cc then
      return security.aer_read_now_out_v1('switch_off', 'course_read_country_off', 'Course entry requirements are not read for ' || coalesce(v_cc, 'this country') || ' (setting Course entry requirements: countries read).',
                                          'A Platform Admin switches the country on in Toolsets & limits.');
    end if;
    if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = v_cid
                  and (coalesce(security.toolset_setting('pipeline', 'aer.schedule_lock_fields'), '[]'::jsonb) ? l.field or l.field = 'all')) then
      return security.aer_read_now_out_v1('human_review_required', 'manual_lock', 'This course''s entry requirements are locked by hand. A lock is a person''s decision, so nothing is read.',
                                          'A Platform Admin lifts the lock if the course should be read.');
    end if;
    if exists (select 1 from pipeline.field_enrich_items f where f.course_id = v_cid and f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased')) then
      return security.aer_read_now_out_v1('in_progress', 'read_in_progress', 'A read of this course is already waiting or running. You can close this page: it carries on, and the result appears here.',
                                          'The reader finishes it, then its rows wait in Layer 4 for a person.');
    end if;
    -- a waiting packet: complete = a person's decision; held = recovery from stored records first
    select * into g from security.aer_pending_packets_v1(null, v_cid) order by created_at limit 1;
    if g.item_id is not null then
      if g.packet_state = 'reviewer_ready' then
        return security.aer_read_now_out_v1('human_review_required', 'packet_ready', 'A complete reviewer packet for this course is waiting in Layer 4. A person decides it; nothing is published until then.', 'Open the item in Layer 4.',
                                            '[]', jsonb_build_object('item_id', g.item_id));
      elsif g.packet_state = 'not_checked' then
        return security.aer_read_now_out_v1('in_progress', 'waiting_for_gate', 'The waiting read has not been checked by the completeness gate yet (job layer4-readiness).', 'The gate checks it on its next run.', '[]', jsonb_build_object('item_id', g.item_id));
      elsif g.packet_state = 'needs_input' then
        return security.aer_read_now_out_v1('human_review_required', 'needs_input', 'The waiting read needs input before it can be decided: ' || coalesce(g.parked_reason, 'parked by the technical lane') || '.',
                                            'A person or the Platform Admin supplies it; the read is not repeated on an unchanged page.', '[]', jsonb_build_object('item_id', g.item_id));
      end if;
      -- technical hold: replay from the stored records (no AI, no fetch)
      if v_replay_on and v_replay_left > 0 then
        p := security.aer_replay_plan_v1(g.item_id);
        if coalesce((p->>'ok')::boolean, false) then
          return security.aer_read_now_out_v1('queued', 'replay_from_stored_records', 'The held read can be recovered from its stored records. It is replaced by a complete read for a person to decide; nothing is read again from the web.', 'Open the item in Layer 4 once it is replaced.',
                                              jsonb_build_array(jsonb_build_object('kind', 'replay_item', 'item_id', g.item_id)), jsonb_build_object('item_id', g.item_id));
        end if;
      end if;
      if not v_e13_on then
        return security.aer_read_now_out_v1('switch_off', 'e13_recover_off', 'The waiting read is held by the completeness gate. A corrected read from its stored page is possible, but the E13 recovery switch is off (setting Entry requirements: re-read held reads from stored evidence).',
                                            'A Platform Admin decides whether to switch E13 recovery on.', '[]', jsonb_build_object('item_id', g.item_id));
      end if;
      return security.aer_read_now_out_v1('human_review_required', 'needs_input', 'The waiting read is held by the completeness gate and its automatic recovery has already run or is not possible (' || coalesce(left(p->>'why', 160), 'see Layer 4') || ').',
                                          'A person completes it in Layer 4.', '[]', jsonb_build_object('item_id', g.item_id));
    end if;
    select pg.url, pg.status, pg.identity_basis, pg.evidence_id, a.storage_path is not null held, a.captured_at, a.content_hash hash into g from pipeline.coverage_course_pages pg left join pipeline.evidence_artifacts a on a.id = pg.evidence_id where pg.course_id = v_cid;
    if g.url is null then return security.aer_read_now_out_v1('source_unavailable', 'no_course_page', 'No official page is bound to this course, so there is nothing to read.', 'Course-page discovery binds it; a person can add the page. No search is started from here.'); end if;
    if g.status is distinct from 'bound' then return security.aer_read_now_out_v1('source_unavailable', 'course_page_not_bound', 'The course page is not bound to this course (' || coalesce(g.status, 'unknown') || ').', 'The page binding is resolved in course-page discovery.', '[]', jsonb_build_object('url', g.url)); end if;
    if not g.held then return security.aer_read_now_out_v1('source_unavailable', 'no_stored_copy', 'The page is known but no stored copy exists. Fetching it uses the scraper budget, which is not started from here.', 'The page is stored by the course-page crawl.', '[]', jsonb_build_object('url', g.url)); end if;
    if not security.coverage_identity_allowed(v_pid, g.identity_basis, 'entry_requirements') then
      return security.aer_read_now_out_v1('source_unavailable', 'identity_not_admitted', 'The page is matched to the course by ' || replace(coalesce(g.identity_basis, 'an unrecorded basis'), '_', ' ') || ' only, which is not admitted for entry requirements (a Platform Admin decision is pending). It is not read.',
                                          'A Platform Admin decision, or a person confirms the course page.', '[]', jsonb_build_object('url', g.url));
    end if;
    select f.state, f.evidence_id, f.updated_at, f.reason into r from pipeline.field_enrich_items f where f.course_id = v_cid and f.field = 'entry_requirements' and f.state in ('review', 'filled', 'skipped', 'failed') order by f.id desc limit 1;
    -- unchanged evidence is not read again: the same stored copy, or another copy with the same content hash
    v_same := r.state in ('review', 'filled', 'skipped') and (r.evidence_id is not distinct from g.evidence_id
              or exists (select 1 from pipeline.evidence_artifacts e1 join pipeline.evidence_artifacts e2 on e2.content_hash = e1.content_hash where e1.id = r.evidence_id and e2.id = g.evidence_id and e1.content_hash is not null));
    if v_same and r.state = 'skipped' and r.reason in ('the page does not state it', 'no quoted requirement was on the page', 'no row met the admission rules') then
      return security.aer_read_now_out_v1('already_up_to_date', 'tried_not_found', 'The stored copy of this course''s page was read on ' || to_char(r.updated_at at time zone 'Australia/Melbourne', 'DD Mon YYYY') || ' and no entry requirement was kept from it (recorded: "' || r.reason || '"). An unchanged copy is not read again, so nothing is spent.',
                                          'A person can add the requirement or correct the page. It is read again when the page changes or after ' || security.pipeline_num_v1('aer.schedule_retry_days', 30)::int || ' days.', '[]', jsonb_build_object('url', g.url));
    end if;
    if v_same then
      return security.aer_read_now_out_v1('already_up_to_date', 'same_stored_copy', 'This course was read on the current stored copy of its page (' || to_char(r.updated_at at time zone 'Australia/Melbourne', 'DD Mon YYYY') || ')' || case when r.state = 'skipped' then '; recorded: "' || left(coalesce(r.reason, 'no reason recorded'), 160) || '"' else '' end || '. An unchanged copy is not read again, so nothing is spent.',
                                          'It is read again when the page changes or after ' || security.pipeline_num_v1('aer.schedule_retry_days', 30)::int || ' days if it kept nothing.', '[]', jsonb_build_object('url', g.url));
    end if;
    -- asked from here already for this stored copy (same content hash) within the retry interval: not queued again, so a click cannot re-queue a failing read for ever
    if r.state = 'failed' then
    select max(e.created_at) into v_when from pipeline.admin_control_events e where e.area = 'aer_read_now' and e.created_at > now() - make_interval(days => v_retry)
       and e.detail->'started' @> jsonb_build_array(jsonb_build_object('kind', 'read_course', 'course_id', v_cid::text, 'content_hash', coalesce(g.hash, g.evidence_id::text, '')));
    if v_when is not null then
      return security.aer_read_now_out_v1('no_eligible_work', 'technical_failure_retried', 'The last read of this course failed (recorded: "' || left(coalesce(r.reason, 'no reason recorded'), 160) || '") and was already asked again from here on ' || to_char(v_when at time zone 'Australia/Melbourne', 'DD Mon YYYY') || ' against the same stored copy of the page. It is not asked again against an unchanged page.',
                                          'It is read again when the page changes or after ' || v_retry || ' days.', '[]', jsonb_build_object('url', g.url));
    end if;
    end if;
    if v_ai is not null then return security.aer_read_now_out_v1('budget_reached', 'ai_stopped', 'AI reading is stopped (AI limits): ' || v_ai || '. Nothing was asked.', 'It resumes when the AI limit allows.'); end if;
    if v_bal is not null and v_bal - v_cost < v_floor then return security.aer_read_now_out_v1('budget_reached', 'credit_floor', 'The read would take the OpenRouter balance below its floor (Toolsets & limits). Nothing was asked.', 'A Platform Admin tops up or lowers the floor.'); end if;
    if r.state = 'failed' then
      return security.aer_read_now_out_v1('queued', 'technical_failure_retry', 'The last read of this course failed (recorded: "' || left(coalesce(r.reason, 'no reason recorded'), 160) || '"). It will be read again from the stored copy of its official page. No scraper is used. Its rows wait in Layer 4 for a person.', 'Open the item in Layer 4 when it arrives.',
                                          jsonb_build_array(jsonb_build_object('kind', 'read_course', 'course_id', v_cid, 'content_hash', coalesce(g.hash, g.evidence_id::text, ''))), jsonb_build_object('url', g.url, 'estimate_usd', round(v_cost, 4)));
    end if;
    return security.aer_read_now_out_v1('queued', 'course_read', 'The course will be read from the stored copy of its official page. No scraper is used. Its rows wait in Layer 4 for a person.', 'Open the item in Layer 4 when it arrives.',
                                        jsonb_build_array(jsonb_build_object('kind', 'read_course', 'course_id', v_cid, 'content_hash', coalesce(g.hash, g.evidence_id::text, ''))), jsonb_build_object('url', g.url, 'estimate_usd', round(v_cost, 4)));
  end if;

  ---------------------------------------------------------------------------------------------------------------------------------- one provider (the university's matrix and its course-level reading)
  if not exists (select 1 from security.aer_eligible_v1() e where e.provider_id = v_pid) then
    return security.aer_read_now_out_v1('no_eligible_work', 'not_aer_eligible', 'This provider is outside entry-requirements reading (it must be an active, published provider that enrols international students, in a country that is read).', null);
  end if;
  if not coalesce((security.aer_schedule_country_v1(v_cc)->>'on')::boolean, false) then
    return security.aer_read_now_out_v1('switch_off', 'country_off', 'Entry-requirements reading is switched off for ' || coalesce(v_cc, 'this country') || ': ' || coalesce(security.aer_schedule_country_v1(v_cc)->>'reason', 'switched off') || '.', 'A Platform Admin switches the country on in Toolsets & limits.');
  end if;
  select count(*) into v_inflight from (
    select 1 from pipeline.entry_matrix_runs mr where mr.provider_id = v_pid and mr.state in ('queued', 'leased')
    union all select 1 from pipeline.entry_matrix_sources s where s.provider_id = v_pid and s.status in ('found', 'reading')
    union all select 1 from pipeline.field_enrich_items f where f.provider_id = v_pid and f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased')) z;
  if v_inflight > 0 then
    return security.aer_read_now_out_v1('in_progress', 'work_in_flight', v_inflight || ' read(s) for this provider are already waiting or running. You can close this page: they carry on, and the stages below update.', 'The reader finishes them, then the rows wait in Layer 4 for a person.',
                                        '[]', jsonb_build_object('in_flight', v_inflight));
  end if;
  select count(*) filter (where packet_state = 'reviewer_ready'), count(*) filter (where packet_state = 'technical_hold'), count(*) filter (where packet_state = 'needs_input'), count(*) filter (where packet_state = 'not_checked'),
         array_agg(item_id order by created_at, item_id) filter (where packet_state = 'technical_hold' and field_code = 'course_entry_first_read')
    into v_ready, v_hold, v_input, v_chk, v_hold_ids from security.aer_pending_packets_v1(v_pid, null);  -- one scoped call; the held ids are passed down to the replay step below
  select count(*) into v_srcs from pipeline.entry_matrix_sources s where s.provider_id = v_pid;
  select coalesce(sum(x.course_reads + x.corrections), 0) into v_used from pipeline.aer_schedule_runs x where x.ran_at > now() - interval '1 day';  -- fixed: the daily cap is counted over the last 24 hours, reads and corrections together, as the scheduled reader counts it
  select coalesce(sum(coalesce((e.detail->>'course_reads')::int, 0) + coalesce((e.detail->>'rereads')::int, 0) + coalesce((e.detail->>'replays')::int, 0)), 0) into v_od from pipeline.admin_control_events e where e.area = 'aer_read_now' and e.created_at > now() - interval '1 day';  -- fixed: same window; course reads, source reads again and replays asked from here all count against the shared daily allowance
  select count(*), count(*) filter (where exists (select 1 from pipeline.work_items w where w.lane = 'aer_technical' and w.work_kind = 'l4_item' and w.entity = i.id::text and w.stage = 'parked' and w.unresolved_blocker->>'action' = 'park'))
    into v_l4, v_parked from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run');  -- fixed: the two kinds the scheduled reading counts
  select count(*) into v_prog from pipeline.field_enrich_items f where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased');

  -- (a) a source whose latest read failed technically is read again from its stored copy (not a held_unparsed source, not a markdown copy: those are fetched again by the entry reader under its own guard)
  for r in select s.id, s.url, lr.content_hash h from pipeline.entry_matrix_sources s
            join lateral (select * from pipeline.entry_matrix_runs mr where mr.source_id = s.id order by (mr.content_hash is not distinct from s.content_hash) desc, mr.created_at desc limit 1) lr on true
            left join pipeline.evidence_artifacts ev on ev.id = s.evidence_id
           where s.provider_id = v_pid and s.status = 'read' and lr.state = 'failed' and coalesce(lr.error, '') not like 'held%' and ev.storage_path is not null and coalesce(ev.mime_type, '') <> 'text/markdown'
              -- once asked from here for this page (same content hash) a failed read is not queued again before the retry interval (setting Entry requirements: retry days)
              and not exists (select 1 from pipeline.admin_control_events e where e.area = 'aer_read_now' and e.created_at > now() - make_interval(days => v_retry)
                                and e.detail->'started' @> jsonb_build_array(jsonb_build_object('kind', 'reread_source', 'source_id', s.id::text, 'content_hash', coalesce(lr.content_hash, ''))))
           order by s.read_at nulls first, s.id limit v_srcmax loop
    if not security.entry_matrix_enabled_v1(v_pid) then v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('outcome', 'switch_off', 'reason', 'matrix_reader_off', 'text', 'The entry-matrix reader does not read this provider (settings Entry matrices: reader on and providers).')); exit;
    elsif v_aim is not null then v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('outcome', 'budget_reached', 'reason', 'ai_stopped', 'text', 'AI reading of entry matrices is stopped (AI limits): ' || v_aim || '.')); exit;
    end if;
    v_actions := v_actions || jsonb_build_array(jsonb_build_object('kind', 'reread_source', 'source_id', r.id, 'url', r.url, 'content_hash', coalesce(r.h, '')));
  end loop;
  -- (b) held course reads that the stored records can replace (no AI, no fetch), within the replay switch, its per-provider and daily caps
  if v_hold > 0 then
    if not v_replay_on then v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('outcome', 'switch_off', 'reason', 'replay_off', 'text', v_hold || ' held read(s) could be replaced from stored records, but that recovery is switched off (setting Entry requirements: recover held reads from stored records).'));
    elsif v_replay_left <= 0 then v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('outcome', 'budget_reached', 'reason', 'replay_daily_cap', 'text', 'The daily allowance of replays from stored records is used.'));
    else
      v_n := 0;
      for r in select h.item_id from unnest(coalesce(v_hold_ids, '{}'::uuid[])) with ordinality h(item_id, ord) left join pipeline.aer_replay_checks k on k.item_id = h.item_id
                order by k.checked_at nulls first, h.ord limit v_replay_per loop
        p := security.aer_replay_plan_v1(r.item_id);
        if coalesce((p->>'ok')::boolean, false) and v_n < least(v_replay_per, v_replay_left) then
          v_actions := v_actions || jsonb_build_array(jsonb_build_object('kind', 'replay_item', 'item_id', r.item_id)); v_n := v_n + 1;
        end if;
      end loop;
    end if;
    if not v_e13_on and v_n = 0 then v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('outcome', 'switch_off', 'reason', 'e13_recover_off', 'text', v_hold || ' read(s) are held by the completeness gate; a corrected read from the stored page needs the E13 recovery switch, which is off.')); end if;
  end if;
  -- (c) first reads of courses whose bound page is already stored (the scheduled reader's own population and function), within Layer 4 room, the daily cap, the AI guard and the credit floor
  select count(*) into v_elig from security.aer_course_population_v1(v_pid) q
   where not exists (select 1 from pipeline.field_enrich_items f where f.course_id = q.course_id and f.field = 'entry_requirements')
     and not exists (select 1 from pipeline.layer4_review_items i where i.entity_id = q.course_id and i.field_code = 'course_entry_first_read' and i.status = 'pending');
  if v_elig > 0 then
    v_room := least(v_per, v_daymax - v_used - v_od, v_l4max - (v_l4 - v_parked + v_prog));
    if v_ai is not null then v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('outcome', 'budget_reached', 'reason', 'ai_stopped', 'text', 'AI reading is stopped (AI limits): ' || v_ai || '. ' || v_elig || ' course(s) are waiting to be read.'));
    elsif v_bal is not null and v_bal - least(v_per, v_elig) * v_cost < v_floor then v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('outcome', 'budget_reached', 'reason', 'credit_floor', 'text', 'Reading courses would take the OpenRouter balance below its floor (Toolsets & limits).'));
    elsif v_daymax - v_used - v_od <= 0 then v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('outcome', 'budget_reached', 'reason', 'daily_cap', 'text', 'The daily allowance of course reads (' || v_daymax || ') is used, scheduled and on demand together.'));
    elsif v_l4max - (v_l4 - v_parked + v_prog) <= 0 then v_blocks := v_blocks || jsonb_build_array(jsonb_build_object('outcome', 'human_review_required', 'reason', 'layer4_full', 'text', 'Layer 4 holds ' || (v_l4 - v_parked) || ' entry-requirement items for a person (limit ' || v_l4max || '). No new course read starts until decisions are made; ' || v_elig || ' course(s) of this provider are waiting.'));
    else
      select array_agg(q.course_id order by q.title, q.course_id) into v_pick from (
        select q0.course_id, q0.title from security.aer_course_population_v1(v_pid) q0
         where not exists (select 1 from pipeline.field_enrich_items f where f.course_id = q0.course_id and f.field = 'entry_requirements')
           and not exists (select 1 from pipeline.layer4_review_items i where i.entity_id = q0.course_id and i.field_code = 'course_entry_first_read' and i.status = 'pending')
         order by q0.title, q0.course_id limit v_room) q;
      if v_pick is not null then v_actions := v_actions || coalesce((select jsonb_agg(jsonb_build_object('kind', 'read_course', 'course_id', c)) from unnest(v_pick) c), '[]'::jsonb); end if;
    end if;
  end if;

  v_extra := jsonb_build_object('packets', jsonb_build_object('reviewer_ready', v_ready, 'technical_hold', v_hold, 'needs_input', v_input, 'not_checked', v_chk), 'courses_waiting_to_be_read', v_elig, 'sources', v_srcs, 'blocks', v_blocks);
  if jsonb_array_length(v_actions) > 0 then
    if not exists (select 1 from jsonb_array_elements(v_actions) x where x->>'kind' <> 'reread_source') then
      return security.aer_read_now_out_v1('queued', 'technical_failure_retry', jsonb_array_length(v_actions) || ' source(s) whose last read failed technically are read again from their stored copy. No fetch, no page search. Every result waits in Layer 4 for a person.', 'Watch the stages below, or open Layer 4 when rows arrive.', v_actions, v_extra);
    end if;
    return security.aer_read_now_out_v1('queued', 'work_started', 'Starting ' || jsonb_array_length(v_actions) || ' read(s) from what is already stored: no scraper, no page search. Every result waits in Layer 4 for a person.', 'Watch the stages below, or open Layer 4 when rows arrive.', v_actions, v_extra);
  end if;
  -- nothing to start: say exactly why, most specific first
  for r in select b->>'outcome' o, b from jsonb_array_elements(v_blocks) b order by array_position(array['switch_off', 'budget_reached', 'human_review_required', 'source_unavailable'], b->>'outcome') nulls last loop
    return security.aer_read_now_out_v1(r.o, r.b->>'reason', r.b->>'text', null, '[]', v_extra);
  end loop;
  if v_ready > 0 or v_input > 0 then
    return security.aer_read_now_out_v1('human_review_required', case when v_ready > 0 then 'packet_ready' else 'needs_input' end,
      case when v_ready > 0 then v_ready || ' complete reviewer packet(s) are waiting in Layer 4 for a person.' else v_input || ' waiting read(s) need input before a person can decide them.' end || ' Nothing is published until a person decides.', 'Open the items in Layer 4.', '[]', v_extra);
  end if;
  if v_srcs > 0 or v_hold > 0 or v_chk > 0 then
    if v_hold + v_chk > 0 then return security.aer_read_now_out_v1('in_progress', 'waiting_for_recovery', (v_hold + v_chk) || ' waiting read(s) are held by the completeness gate; automatic recovery handles them on its next run.', 'Job aer-replay and the gate run hourly.', '[]', v_extra); end if;
    -- what each source actually recorded (a source that is only waiting is "in flight" above). Only a source read by a finished run that kept no row is "read, nothing kept". A read the reader HELD (held_unparsed, held_incomplete, held: ...) found nothing absent: the reader could not read the page reliably.
    select count(*) filter (where s.status = 'failed') n_fail, count(*) filter (where s.status = 'robots_disallowed') n_robots,
           count(*) filter (where s.status = 'read' and lr.state = 'done' and coalesce(lr.rows_admitted, 0) = 0) n_none,
           count(*) filter (where s.status = 'read' and lr.state = 'done' and coalesce(lr.rows_admitted, 0) > 0) n_rows,
           count(*) filter (where s.status = 'read' and lr.state = 'failed' and lr.error like 'held%') n_held,
           count(*) filter (where s.status = 'read' and lr.state = 'failed' and coalesce(lr.error, '') not like 'held%') n_rfail,
           min(s.url) filter (where s.status = 'failed') u_fail, min(coalesce(s.error, '')) filter (where s.status = 'failed') e_fail, min(s.url) filter (where s.status = 'robots_disallowed') u_robots,
           min(s.url) filter (where s.status = 'read' and lr.state = 'done' and coalesce(lr.rows_admitted, 0) = 0) u_none,
           min(s.url) filter (where s.status = 'read' and lr.state = 'failed' and lr.error like 'held%') u_held, min(coalesce(lr.error, '')) filter (where s.status = 'read' and lr.state = 'failed' and lr.error like 'held%') e_held,
           min(s.url) filter (where s.status = 'read' and lr.state = 'failed' and coalesce(lr.error, '') not like 'held%') u_rfail, min(coalesce(lr.error, '')) filter (where s.status = 'read' and lr.state = 'failed' and coalesce(lr.error, '') not like 'held%') e_rfail
      into v_sn
      from pipeline.entry_matrix_sources s
      left join lateral (select mr.state, mr.rows_admitted, mr.error from pipeline.entry_matrix_runs mr where mr.source_id = s.id order by (mr.content_hash is not distinct from s.content_hash) desc, mr.created_at desc limit 1) lr on true
     where s.provider_id = v_pid and s.status <> 'inactive';
    v_extra := v_extra || jsonb_build_object('source_counts', jsonb_build_object('read_with_rows_kept', v_sn.n_rows, 'read_nothing_kept', v_sn.n_none, 'held_by_the_reader', v_sn.n_held, 'read_failed', v_sn.n_rfail, 'fetch_failed', v_sn.n_fail, 'robots_disallowed', v_sn.n_robots));
    if v_sn.n_fail > 0 then
      return security.aer_read_now_out_v1('source_unavailable', 'source_fetch_failed', v_sn.n_fail || ' source(s) could not be fetched or opened (first: ' || v_sn.u_fail || '; recorded: "' || coalesce(nullif(left(v_sn.e_fail, 120), ''), 'no reason recorded') || '"). The page is not stored, so there is nothing to read again from here.',
        'It is fetched again after ' || security.pipeline_num_v1('entry.matrix_refresh_days', 30)::int || ' days, or a person checks or replaces the page.', '[]', v_extra);
    end if;
    if v_sn.n_robots > 0 then
      return security.aer_read_now_out_v1('source_unavailable', 'robots_disallowed', v_sn.n_robots || ' source(s) are disallowed by the website''s robots.txt (first: ' || v_sn.u_robots || '). They are not fetched.', 'A person supplies the page another way, or leaves it.', '[]', v_extra);
    end if;
    if v_sn.n_held > 0 then
      return security.aer_read_now_out_v1('human_review_required', 'reader_held', v_sn.n_held || ' source(s) were read but the reader held them (first: ' || v_sn.u_held || '; recorded: "' || coalesce(nullif(left(v_sn.e_held, 120), ''), 'no reason recorded') || '"). The reader could not read the page reliably, so nothing is known about what it states.',
        'A reader change under change control, or a person supplying the table, reads it again. It is not read again against an unchanged page.', '[]', v_extra);
    end if;
    if v_sn.n_rfail > 0 then
      return security.aer_read_now_out_v1('no_eligible_work', 'technical_failure_retried', v_sn.n_rfail || ' source(s) have a read that failed technically (first: ' || v_sn.u_rfail || '; recorded: "' || coalesce(nullif(left(v_sn.e_rfail, 120), ''), 'no reason recorded') || '"). It is not asked again from here against an unchanged page.',
        'It is read again when the page changes, or after ' || v_retry || ' days if it was already asked from here. A person can use Read again under the advanced controls.', '[]', v_extra);
    end if;
    if v_sn.n_none > 0 then
      return security.aer_read_now_out_v1('already_up_to_date', 'tried_not_found', v_sn.n_none || ' source(s) were read to the end and no entry-requirement row was kept from them (first: ' || v_sn.u_none || '). An unchanged page is not read again, so nothing is spent.',
        'A person can correct or replace the page. It is fetched again after ' || security.pipeline_num_v1('entry.matrix_refresh_days', 30)::int || ' days and read again only if it changed.', '[]', v_extra);
    end if;
    return security.aer_read_now_out_v1('already_up_to_date', 'sources_read', 'Every source of this provider has been read on its current stored copy. A page that has not changed is not read again, so nothing is spent.', 'Pages are fetched again after ' || security.pipeline_num_v1('entry.matrix_refresh_days', 30)::int || ' days, and read again only if they changed.', '[]', v_extra);
  end if;
  select coalesce(f.evidence->>'route', 'not_classified') into v_route from pipeline.aer_gap_findings f where f.provider_id = v_pid and f.root_cause = 'no_source' and f.state <> 'resolved' order by f.last_seen desc limit 1;
  if v_route is null then return security.aer_read_now_out_v1('no_eligible_work', 'nothing_to_read', 'No source, matched course page or waiting read needs work for this provider right now.', null, '[]', v_extra); end if;
  return case v_route
    when 'source_page_stored' then security.aer_read_now_out_v1(case when v_sf_on then 'source_unavailable' else 'switch_off' end, case when v_sf_on then 'stored_page_not_yet_attached' else 'stored_find_off' end,
        case when v_sf_on then 'A stored link on the provider''s own website scores as its entry-requirements page, but it is not attached as a source yet.' else 'A stored link scores as the provider''s entry-requirements page, but attaching it is switched off (setting Entry pages from stored links: on).' end,
        'Job aer-source-stored-find attaches it on its next hourly run' || case when v_sf_on then '.' else ' once a Platform Admin switches it on.' end, '[]', v_extra)
    when 'course_pages_waiting' then security.aer_read_now_out_v1('no_eligible_work', 'courses_already_read', 'Every course page of this provider that can be read has been read or is waiting in Layer 4.', null, '[]', v_extra)
    when 'course_pages_unconfirmed' then security.aer_read_now_out_v1('source_unavailable', 'identity_not_admitted', 'Course pages are stored but matched to their courses by title only, which is not admitted for entry requirements (a Platform Admin decision is pending). None is read.', 'A Platform Admin decision, or a person confirms each course page.', '[]', v_extra)
    when 'source_page_host_shared' then security.aer_read_now_out_v1('source_unavailable', 'host_shared', 'A stored entry-requirements page exists, but its website is also used by another active provider, so it is not attached by itself.', 'A person confirms which provider the website and the page belong to.', '[]', v_extra)
    when 'weak_page_only' then security.aer_read_now_out_v1('source_unavailable', 'weak_page_only', 'Only a general entry-requirements page is stored, under the score for a suggestion.', 'Lower Find central pages: minimum score (not under 3), or a person confirms the page.', '[]', v_extra)
    when 'nothing_stored' then security.aer_read_now_out_v1('source_unavailable', 'nothing_stored', 'Nothing is stored to read: no entry-requirements link and no matched course page. A page search would use scraper credits, so it is not started from here.', 'A person adds the entry-requirements page, or a search is requested when the budget allows.', '[]', v_extra)
    else security.aer_read_now_out_v1('no_eligible_work', 'nothing_to_read', 'No source, matched course page or waiting read needs work for this provider right now.', null, '[]', v_extra) end;
end $f$;
revoke all on function security.aer_read_now_plan_v1(uuid, uuid) from public, anon, authenticated;
comment on function security.aer_read_now_plan_v1(uuid, uuid) is 'CF-247 AER read now (10 Nov 2026): what one click of Read / refresh entry requirements now would do for a provider or a course, or why it would do nothing, as one outcome (queued, in_progress, human_review_required, already_up_to_date, no_eligible_work, source_unavailable, switch_off, budget_reached) with a plain reason and the actions it would take. Reuses stored copies before any paid call; starts no scraper, no page search and no E13 AI re-read. Read only.';

-- 5. the stage timeline ---------------------------------------------------------------------------------------------------------------------
create or replace function security.aer_read_now_status_v1(p_provider uuid, p_course uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $f$
declare
  v_pid uuid; v_cid uuid; v_pname text; v_ctitle text; v_cc text; v_plan jsonb; v_stages jsonb; v_last jsonb; v_facts jsonb;
  v_src int := 0; v_stored int := 0; v_srcread int := 0; v_read_at timestamptz; v_pages int := 0; v_prop_m int := 0; v_prop_c int := 0; v_runs_done int := 0; v_runs_held int := 0;
  v_ready int := 0; v_hold int := 0; v_input int := 0; v_chk int := 0; v_act_m int := 0; v_act_c int := 0; v_approved int := 0; v_rejected int := 0; v_pub text; v_cls timestamptz;
  v_rr int := 0; v_rc int := 0; v_rf int := 0; v_rns jsonb := '{}'::jsonb; v_next timestamptz; v_ready_ids uuid[];
begin
  if p_course is not null then
    select c.id, c.provider_id, coalesce(c.display_title, c.canonical_title) into v_cid, v_pid, v_ctitle from catalogue.courses c where c.id = p_course;
  else v_pid := p_provider; end if;
  select coalesce(pv.display_name, pv.canonical_name), k.iso_alpha2::text, pv.publication_status into v_pname, v_cc, v_pub from catalogue.providers pv left join ref.countries k on k.id = pv.country_id where pv.id = v_pid;
  if v_pname is null then return jsonb_build_object('known', false, 'reason', 'That provider or course was not found.'); end if;
  v_plan := security.aer_read_now_plan_v1(v_pid, v_cid);
  select count(*) filter (where packet_state = 'reviewer_ready'), count(*) filter (where packet_state = 'technical_hold'), count(*) filter (where packet_state = 'needs_input'), count(*) filter (where packet_state = 'not_checked'), max(classified_at),
         array_agg(item_id) filter (where packet_state = 'reviewer_ready')
    into v_ready, v_hold, v_input, v_chk, v_cls, v_ready_ids from security.aer_pending_packets_v1(v_pid, v_cid);  -- one scoped call; the ready ids are passed to the facts check below
  -- facts of the reviewer-ready packets only (rows of a held packet are not yet a packet)
  select count(*), count(*) filter (where x.country <> 'not_stated' and x.qualification <> 'not_stated' and x.grade <> 'not_stated' and x.scale <> 'not_stated' and x.applicability <> 'not_stated' and x.source_page <> 'not_stated' and x.year <> 'not_stated'),
         jsonb_strip_nulls(jsonb_build_object('country', nullif(count(*) filter (where x.country = 'not_stated'), 0), 'qualification', nullif(count(*) filter (where x.qualification = 'not_stated'), 0), 'grade', nullif(count(*) filter (where x.grade = 'not_stated'), 0),
              'scale', nullif(count(*) filter (where x.scale = 'not_stated'), 0), 'applicability', nullif(count(*) filter (where x.applicability = 'not_stated'), 0), 'source_page', nullif(count(*) filter (where x.source_page = 'not_stated'), 0),
              'year', nullif(count(*) filter (where x.year = 'not_stated'), 0)))
    into v_rr, v_rc, v_rns
    from security.aer_packet_rows_v1(null) x
   where x.item_id = any (coalesce(v_ready_ids, '{}'::uuid[])) and (v_cid is null or x.course_id = v_cid) and (x.provider_id = v_pid);
  v_rf := v_rr - v_rc;
  if v_cid is null then
    select count(*), count(*) filter (where s.evidence_id is not null), count(*) filter (where s.status = 'read'), max(s.read_at) into v_src, v_stored, v_srcread, v_read_at from pipeline.entry_matrix_sources s where s.provider_id = v_pid;
    select count(*) into v_pages from pipeline.coverage_course_pages g join catalogue.courses c on c.id = g.course_id join pipeline.evidence_artifacts a on a.id = g.evidence_id and a.storage_path is not null
     where c.provider_id = v_pid and c.lifecycle_status = 'active' and g.status = 'bound';
    select count(*) into v_prop_m from catalogue.provider_entry_matrix m where m.provider_id = v_pid and m.status = 'proposed';
    select count(*) into v_prop_c from catalogue.course_entry_requirements q join catalogue.courses c on c.id = q.course_id where c.provider_id = v_pid and q.status = 'proposed';
    select count(*) filter (where r.state = 'done'), count(*) filter (where r.state = 'failed') into v_runs_done, v_runs_held from pipeline.entry_matrix_runs r where r.provider_id = v_pid;
    select count(*) into v_act_m from catalogue.provider_entry_matrix m where m.provider_id = v_pid and m.status = 'active';
    select count(*) into v_act_c from catalogue.course_entry_requirements q join catalogue.courses c on c.id = q.course_id where c.provider_id = v_pid and q.status = 'active';
    select count(*) filter (where i.status in ('approved', 'edited_approved')), count(*) filter (where i.status = 'rejected') into v_approved, v_rejected
      from pipeline.layer4_review_items i left join catalogue.courses c on i.entity_type = 'course' and c.id = i.entity_id
     where i.field_code = any (security.aer_review_kinds_v1()) and coalesce(c.provider_id, case when i.entity_type = 'provider' then i.entity_id end) = v_pid;
  else
    select count(*), count(*) filter (where a.storage_path is not null) into v_src, v_stored from pipeline.coverage_course_pages g left join pipeline.evidence_artifacts a on a.id = g.evidence_id where g.course_id = v_cid and g.status = 'bound';
    v_pages := v_src;
    select count(*) into v_prop_c from catalogue.course_entry_requirements q where q.course_id = v_cid and q.status = 'proposed';
    select count(*) filter (where f.state in ('review', 'filled', 'skipped')), count(*) filter (where f.state = 'failed') into v_runs_done, v_runs_held from pipeline.field_enrich_items f where f.course_id = v_cid and f.field = 'entry_requirements';
    select max(f.updated_at) into v_read_at from pipeline.field_enrich_items f where f.course_id = v_cid and f.field = 'entry_requirements' and f.state in ('review', 'filled', 'skipped');
    select count(*) into v_act_c from catalogue.course_entry_requirements q where q.course_id = v_cid and q.status = 'active';
    select count(*) filter (where i.status in ('approved', 'edited_approved')), count(*) filter (where i.status = 'rejected') into v_approved, v_rejected
      from pipeline.layer4_review_items i where i.entity_type = 'course' and i.entity_id = v_cid and i.field_code = 'course_entry_first_read';
  end if;
  select jsonb_build_object('event', e.id, 'at', e.created_at, 'by', e.actor, 'outcome', e.detail->>'outcome', 'reason', e.detail->>'reason', 'started', e.detail->'started', 'note', e.detail->>'note')
    into v_last from pipeline.admin_control_events e where e.area = 'aer_read_now' and e.target = coalesce(v_cid, v_pid)::text order by e.id desc limit 1;
  select security.cron_next_run_v1(j.schedule, now()) into v_next from cron.job j where j.jobname = 'aer-scheduled-read' and j.active;
  v_stages := jsonb_build_array(
    jsonb_build_object('key', 'source_found', 'label', 'Source found', 'state', case when v_cid is not null then case when v_stored > 0 then 'done' else 'none' end when v_src > 0 or v_pages > 0 then 'done' else 'none' end,
      'n', case when v_cid is not null then v_stored else v_src end, 'unit', case when v_cid is not null then 'stored course page' else 'entry source' end,
      'detail', case when v_cid is not null then case when v_stored > 0 then 'The official course page is stored and bound.' else 'No stored copy of an official course page.' end
                     else v_src || ' entry source(s), ' || v_stored || ' with a stored copy; ' || v_pages || ' bound course page(s) stored' || case when v_read_at is not null then '; last read ' || to_char(v_read_at at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI') else '' end end),
    jsonb_build_object('key', 'parsed', 'label', 'AI parsed candidates', 'state', case when v_prop_m + v_prop_c > 0 then 'done' when v_runs_done > 0 then 'partial' else 'none' end, 'n', v_prop_m + v_prop_c, 'unit', 'candidate row',
      'detail', (v_prop_m + v_prop_c) || ' candidate row(s) waiting (' || v_prop_m || ' university table, ' || v_prop_c || ' course); ' || v_runs_done || ' read(s) done' || case when v_runs_held > 0 then ', ' || v_runs_held || ' failed or held' else '' end || '. Candidates are not admissions.'),
    jsonb_build_object('key', 'packet', 'label', 'Complete reviewer packet', 'state', case when v_ready > 0 then 'done' when v_hold + v_input + v_chk > 0 then 'partial' else 'none' end, 'n', v_ready, 'unit', 'packet',
      'detail', v_ready || ' complete (' || v_rc || ' of ' || v_rr || ' rows state every fact' || case when v_rf > 0 then '; ' || v_rf || ' have a fact not stated, flagged for the reviewer' else '' end || '); ' || v_hold || ' held by the completeness gate, ' || v_input || ' need input, ' || v_chk || ' not checked yet.'),
    jsonb_build_object('key', 'human', 'label', 'Awaiting a person in Layer 4', 'state', case when v_ready > 0 then 'waiting' when v_approved + v_rejected > 0 then 'done' else 'none' end, 'n', v_ready, 'unit', 'decision',
      'detail', v_ready || ' packet(s) ready for a person to decide; ' || v_approved || ' approved and ' || v_rejected || ' rejected to date. Nothing is active until a person approves.'),
    jsonb_build_object('key', 'active', 'label', 'Approved and active', 'state', case when v_act_m + v_act_c > 0 then 'done' else 'none' end, 'n', v_act_m + v_act_c, 'unit', 'active row',
      'detail', v_act_m || ' university table row(s) and ' || v_act_c || ' course row(s) are active canonical rows.'),
    jsonb_build_object('key', 'consumer', 'label', 'Visible to the website', 'state', 'unknown', 'n', null, 'unit', null,
      'detail', 'Not measured for one ' || case when v_cid is null then 'provider' else 'course' end || ' here. Active rows reach the website when the ' || case when v_cid is null then 'provider' else 'course' end || ' is published' || case when v_pub is not null then ' (provider: ' || v_pub || ')' else '' end || '; the Website and Zoho read-back is in Operations › Data Delivery.'));
  return jsonb_build_object('known', true, 'scope', case when v_cid is null then 'provider' else 'course' end,
    'provider', jsonb_build_object('id', v_pid, 'name', v_pname, 'country', v_cc), 'course', case when v_cid is not null then jsonb_build_object('id', v_cid, 'title', v_ctitle) end,
    'stages', v_stages, 'outcome', (v_plan - 'actions' - 'blocks') || jsonb_build_object('class', security.aer_read_now_class_v1(v_plan->>'outcome', v_plan->>'reason')), 'source', security.aer_read_now_source_v1(v_pid, v_cid),
    'will_do', coalesce(v_plan->'actions', '[]'::jsonb),
    'blocks', (select coalesce(jsonb_agg(b || jsonb_build_object('class', security.aer_read_now_class_v1(b->>'outcome', b->>'reason'))), '[]'::jsonb) from jsonb_array_elements(coalesce(v_plan->'blocks', '[]'::jsonb)) b), 'last_request', v_last,
    'facts', jsonb_build_object('rows_in_reviewer_ready_packets', v_rr, 'rows_every_fact_stated', v_rc, 'rows_with_a_fact_not_stated', v_rf, 'not_stated', v_rns),
    'next_scheduled_read', v_next, 'packets_classified_at', v_cls, 'counted_at', now());
end $f$;
revoke all on function security.aer_read_now_status_v1(uuid, uuid) from public, anon, authenticated;
comment on function security.aer_read_now_status_v1(uuid, uuid) is 'CF-247 AER read now (10 Nov 2026): the stage timeline of one provider or course (source found, AI parsed candidates, complete reviewer packet, awaiting a person, approved and active, consumer visible) with counts from the existing tables, the facts check of the reviewer-ready packets, the last request and what the next click would do. Read only; a packet awaiting a person is never reported as published.';

-- 6. the action -----------------------------------------------------------------------------------------------------------------------------
create or replace function security.aer_read_now_v1(p_provider uuid, p_course uuid, p_note text, p_actor uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $f$
declare v_key text := coalesce(p_course, p_provider)::text; v_plan jsonb; a jsonb; v_reason text; v_started jsonb := '[]'::jsonb; v_skipped jsonb := '[]'::jsonb; v_reads int := 0; v_rereads int := 0; v_replays int := 0; v_ev bigint; v_job uuid; v_res jsonb; v_out text; v_why text;
begin
  if p_provider is null and p_course is null then raise exception 'a provider or a course is required' using errcode = '22023'; end if;
  -- one click at a time for one scope: a second click waits here, then finds the first one's work in flight and starts nothing (idempotent)
  perform pg_advisory_xact_lock(hashtext('cf247:aer-read-now:' || v_key));
  v_reason := 'Read / refresh entry requirements now' || coalesce(' - ' || nullif(btrim(left(p_note, 300)), ''), '');
  v_plan := security.aer_read_now_plan_v1(p_provider, p_course);
  v_out := v_plan->>'outcome'; v_why := v_plan->>'reason';
  if v_out = 'queued' then
    for a in select x from jsonb_array_elements(v_plan->'actions') x loop
      begin
        if a->>'kind' = 'read_course' then
          v_job := security.course_entry_read_enqueue_v1((a->>'course_id')::uuid, p_actor, v_reason);
          v_started := v_started || jsonb_build_array(jsonb_build_object('kind', 'read_course', 'course_id', a->>'course_id', 'job_id', v_job, 'content_hash', coalesce(a->>'content_hash', ''))); v_reads := v_reads + 1;
        elsif a->>'kind' = 'reread_source' then
          v_res := security.aer_reread_v1((a->>'source_id')::uuid, v_reason, p_actor);
          v_started := v_started || jsonb_build_array(jsonb_build_object('kind', 'reread_source', 'source_id', a->>'source_id', 'run', v_res->>'run', 'content_hash', coalesce(a->>'content_hash', ''))); v_rereads := v_rereads + 1;
        elsif a->>'kind' = 'replay_item' then
          v_res := security.aer_replay_apply_v1((a->>'item_id')::uuid, security.aer_replay_plan_v1((a->>'item_id')::uuid));
          if not coalesce((v_res->>'applied')::boolean, false) then raise exception 'the replay was not applied: %', coalesce(v_res->>'why', 'refused'); end if;
          v_started := v_started || jsonb_build_array(jsonb_build_object('kind', 'replay_item', 'item_id', a->>'item_id', 'new_item', v_res->>'new_item', 'applied', v_res->'applied')); v_replays := v_replays + 1;
        end if;
      exception when others then
        v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('action', a, 'why', left(sqlerrm, 300)));
      end;
    end loop;
    if jsonb_array_length(v_started) = 0 then
      v_out := 'no_eligible_work'; v_why := 'refused';
      v_plan := security.aer_read_now_out_v1(v_out, v_why, 'Nothing was started: ' || coalesce(v_skipped->0->>'why', 'the reader refused every request') || '.', null, '[]', jsonb_build_object('skipped', v_skipped));
    end if;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('aer_read_now', case when p_course is not null then 'course' else 'provider' end, v_key,
          jsonb_build_object('outcome', v_out, 'reason', v_why, 'note', nullif(btrim(left(p_note, 300)), ''), 'course_reads', v_reads, 'rereads', v_rereads, 'replays', v_replays, 'started', v_started, 'skipped', v_skipped, 'provider_id', coalesce(p_provider, (select c.provider_id from catalogue.courses c where c.id = p_course))), p_actor)
  returning id into v_ev;
  return (v_plan - 'actions') || jsonb_build_object('outcome', v_out, 'reason', v_why, 'class', security.aer_read_now_class_v1(v_out, v_why), 'started', v_started, 'skipped', v_skipped, 'event', v_ev);
end $f$;
revoke all on function security.aer_read_now_v1(uuid, uuid, text, uuid) from public, anon, authenticated;
comment on function security.aer_read_now_v1(uuid, uuid, text, uuid) is 'CF-247 AER read now (10 Nov 2026): runs the plan of Read / refresh entry requirements now for one provider or course, once at a time (a second click starts nothing while work is in flight), through the existing functions only (course_entry_read_enqueue_v1, aer_reread_v1, aer_replay_apply_v1), and records one admin_control_events row (area aer_read_now). It approves, admits and publishes nothing: every result waits in Layer 4 for a person.';

-- 7. the signed-in wrapper ---------------------------------------------------------------------------------------------------------------------
create or replace function public.admin_aer_read_now(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $f$
declare v_rank int := coalesce(security.current_role_rank(), 0); v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_cid uuid := nullif(p_args->>'course_id', '')::uuid; v_action text := coalesce(nullif(p_args->>'action', ''), 'status'); v_st jsonb;
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  if v_pid is null and v_cid is null then raise exception 'provider_id or course_id required' using errcode = '22023'; end if;
  if v_action not in ('status', 'run') then raise exception 'unknown action %', v_action using errcode = '22023'; end if;
  if v_action = 'run' and v_rank < 6 then  -- fixed: the rank of the existing per-course read and per-source read again (Platform Admin)
    return (security.aer_read_now_out_v1('permission_denied', 'rank', 'Reading entry requirements on demand needs the Platform Admin role. Nothing was asked.', 'A Platform Admin can do this, or it waits for the scheduled reader.') - 'actions') || jsonb_build_object('known', true, 'can_run', false);
  end if;
  if v_action = 'run' then
    return security.aer_read_now_v1(v_pid, v_cid, p_args->>'note', auth.uid()) || jsonb_build_object('can_run', true);
  end if;
  v_st := security.aer_read_now_status_v1(v_pid, v_cid);
  return v_st || jsonb_build_object('can_run', v_rank >= 6);  -- fixed: same rank as run
end $f$;
revoke all on function public.admin_aer_read_now(jsonb) from public, anon;
grant execute on function public.admin_aer_read_now(jsonb) to authenticated;
comment on function public.admin_aer_read_now(jsonb) is 'CF-247 AER read now (10 Nov 2026): Read / refresh entry requirements now for one provider or course. action status (any assigned role) returns the stage timeline and the outcome a click would have; action run (Platform Admin) starts the governed work and returns the outcome. Outcomes: queued, in_progress, human_review_required, already_up_to_date, no_eligible_work, source_unavailable, switch_off, budget_reached, permission_denied. Starts no scraper and approves nothing.';

-- 8. the guarded edits --------------------------------------------------------------------------------------------------------------------------
do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure; v_at_before boolean;
begin
  for r in select * from (values
    ('security.aer_course_population_v1()', 'd593eb0aa0fe06b0b4b28c86821bfff5', '39df48e65bc7f0d4c3dcb4cde5d244cc', true, null::text[], null::text[]),
    ('security.data_delivery_aer_v1()', '27a42c5f02d09f518e77bd965814bbe0', 'f66f692580977dcef97f8db5b01b3403', true,
     array[$o$  blk as (select coalesce(jsonb_agg(v.t), '[]'::jsonb) j$o$,
           $o$'layer4_readiness', rv.j, 'last_run', lastrun.j, 'jobs', jobs.j, 'blockers', blk.j)$o$,
           $o$from cov, bycc, disp, gaps, other, prk, lastrun, jobs, sf, srcs, rv, blk);$o$],
     array[$n$  -- 10 Nov 2026 (AER read now): reviewer-ready packets against active approved rows, from the stored completeness gate and the proposed rows (never a gate per item)
  pk as (select * from security.aer_pending_packets_v1(null, null)),
  pf as (select count(*) rows, count(*) filter (where x.country <> 'not_stated' and x.qualification <> 'not_stated' and x.grade <> 'not_stated' and x.scale <> 'not_stated' and x.applicability <> 'not_stated' and x.source_page <> 'not_stated' and x.year <> 'not_stated') complete,
                jsonb_strip_nulls(jsonb_build_object('country', nullif(count(*) filter (where x.country = 'not_stated'), 0), 'qualification', nullif(count(*) filter (where x.qualification = 'not_stated'), 0), 'grade', nullif(count(*) filter (where x.grade = 'not_stated'), 0),
                  'scale', nullif(count(*) filter (where x.scale = 'not_stated'), 0), 'applicability', nullif(count(*) filter (where x.applicability = 'not_stated'), 0), 'source_page', nullif(count(*) filter (where x.source_page = 'not_stated'), 0),
                  'year', nullif(count(*) filter (where x.year = 'not_stated'), 0))) ns
           from security.aer_packet_rows_v1(null) x join pk on pk.item_id = x.item_id and pk.packet_state = 'reviewer_ready'),
  rvw as (select jsonb_build_object('known', true, 'pending', (select count(*) from pk), 'classified_at', (select max(classified_at) from pk),
            'reviewer_ready', (select count(*) from pk where packet_state = 'reviewer_ready'), 'technical_hold', (select count(*) from pk where packet_state = 'technical_hold'),
            'needs_input', (select count(*) from pk where packet_state = 'needs_input'), 'not_checked', (select count(*) from pk where packet_state = 'not_checked'),
            'by_kind', (select coalesce(jsonb_object_agg(z.field_code, jsonb_build_object('pending', z.n, 'reviewer_ready', z.r)), '{}'::jsonb) from (select field_code, count(*) n, count(*) filter (where packet_state = 'reviewer_ready') r from pk group by 1) z),
            'ready_rows', (select jsonb_build_object('rows', pf.rows, 'every_fact_stated', pf.complete, 'with_a_fact_not_stated', pf.rows - pf.complete, 'not_stated', pf.ns) from pf),
            'active_rows', jsonb_build_object('matrix', (select count(*) from catalogue.provider_entry_matrix where status = 'active'), 'course', (select count(*) from catalogue.course_entry_requirements where status = 'active')),
            'decided', (select jsonb_build_object('approved', count(*) filter (where i.status in ('approved', 'edited_approved')), 'rejected', count(*) filter (where i.status = 'rejected'), 'last_decided_at', max(i.decided_at))
                          from pipeline.layer4_review_items i where i.field_code = any (security.aer_review_kinds_v1()) and i.status in ('approved', 'edited_approved', 'rejected')),
            'on_demand', (select jsonb_build_object('requests_24h', count(*), 'last_request_at', max(e.created_at), 'queued_24h', count(*) filter (where e.detail->>'outcome' = 'queued')) from pipeline.admin_control_events e where e.area = 'aer_read_now' and e.created_at > now() - interval '1 day')) j),
  blk as (select coalesce(jsonb_agg(v.t), '[]'::jsonb) j$n$,
           $n$'layer4_readiness', rv.j, 'reviewer', rvw.j, 'last_run', lastrun.j, 'jobs', jobs.j, 'blockers', blk.j)$n$,
           $n$from cov, bycc, disp, gaps, other, prk, lastrun, jobs, sf, srcs, rv, rvw, blk);$n$]),
    ('security.layer4_aer_review_detail_v1(text)', '330e079018c93f8db8a649ed3a08ae12', 'e377494a017ea32e2b5d50f7b87c733c', true,
     array[$o$    jsonb_build_object('key', 'rows', 'title', 'Proposed rows (' || (p->'proposed'->>'count') || ')', 'body', p->'proposed'->'rows'),$o$],
     array[$n$    jsonb_build_object('key', 'facts', 'title', 'Facts the page states', 'body', (security.aer_packet_facts_v1(p_ref::uuid))->'section'),
    jsonb_build_object('key', 'rows', 'title', 'Proposed rows (' || (p->'proposed'->>'count') || ')', 'body', p->'proposed'->'rows'),$n$]),
    ('security.data_delivery_v1()', '208067f054c2f3ac7adb1196e3e8c25c', '74ead0d5a3b7b4e48d4783f25c350865', false,
     array[$o$v_rd jsonb; v_job jsonb;$o$,
           $o$    select coalesce(bool_or((st.value #>> '{}') in ('0', 'false')), false) into v_off from unnest(s.switch_keys) k(key)
      join pipeline.platform_toolset_settings st on st.toolset_key = 'pipeline' and st.key = k.key;$o$,
           $o$else 'No open issues; the scheduled job retries on its next run' end,$o$,
           $o$'open_issues', v_open, 'issue_refs', v_issue_refs,$o$],
     array[$n$v_rd jsonb; v_job jsonb; v_sw text[]; v_sw_all int;$n$,
           $n$    -- 10 Nov 2026 (AER read now): a stream is OFF only when every switch of its lane that exists is off; one optional recovery route that is off (for example a deliberately paused pilot) is named, it does not turn the whole stream off
    select coalesce(array_agg(k.key order by k.key) filter (where (st.value #>> '{}') in ('0', 'false')), '{}'::text[]), count(*) filter (where st.key is not null) into v_sw, v_sw_all from unnest(s.switch_keys) k(key)
      left join pipeline.platform_toolset_settings st on st.toolset_key = 'pipeline' and st.key = k.key;
    v_off := cardinality(v_sw) > 0 and cardinality(v_sw) = v_sw_all;$n$,
           $n$else 'No open issues; the scheduled job retries on its next run' || case when cardinality(v_sw) > 0 then '. Switched off, so these routes do not run: ' || array_to_string(v_sw, ', ') else '' end end,$n$,
           $n$'switches_off', to_jsonb(v_sw), 'open_issues', v_open, 'issue_refs', v_issue_refs,$n$])
  ) v(sig, md5_before, md5_after, must_match, olds, news) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then raise notice '%: already applied', r.sig; continue; end if;
    if r.sig = 'security.aer_course_population_v1()' then
      if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition this change edits (body md5 %)', r.sig, md5(v_src); end if;
      create or replace function security.aer_course_population_v1()
      returns table(course_id uuid, provider_id uuid, country text, provider_name text, tier integer, prio bigint, title text)
      language sql stable security definer set search_path = ''
      as $d$ select * from security.aer_course_population_v1(null::uuid) $d$;
      v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
      if md5(v_src) <> r.md5_after then raise exception '% after the edit has body md5 %, expected %', r.sig, md5(v_src), r.md5_after; end if;
      raise notice '%: applied', r.sig; continue;
    end if;
    v_at_before := md5(v_src) = r.md5_before;
    if md5(v_src) <> r.md5_before then
      if r.must_match then raise exception 'live % differs from the definition this change edits (body md5 %)', r.sig, md5(v_src); end if;
      -- Data Delivery is edited by several streams: the edit is anchored text, applied once to whatever is live
      if position('v_sw_all' in v_src) > 0 then raise notice '%: already carries the switch derivation', r.sig; continue; end if;
    end if;
    v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
    for k in 1 .. array_length(r.olds, 1) loop
      v_c := (length(v_def) - length(replace(v_def, r.olds[k], ''))) / length(r.olds[k]);
      if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', r.sig, k, v_c; end if;
      v_def := replace(v_def, r.olds[k], r.news[k]);
    end loop;
    execute v_def;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- the anchored Data Delivery edit is asserted against the recorded after md5 whenever it was applied to the recorded live body; on a live body that has moved on (another stream edited it) the md5 cannot be known in advance and is reported
    if (r.must_match or v_at_before) and md5(v_src) <> r.md5_after then raise exception '% after the edit has body md5 %, expected %', r.sig, md5(v_src), r.md5_after; end if;
    if not v_at_before then raise notice '%: edited a live body that is not the recorded one (md5 %); body md5 now %', r.sig, r.md5_before, md5(v_src); end if;
    raise notice '%: applied', r.sig;
  end loop;
end $m$;

-- 9. register, post-check -----------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'public.admin_aer_read_now', 'Layer 2', 'Read / refresh entry requirements now: stage timeline and one governed action for a provider or a course (status for any role; run for the Platform Admin)', 'active', '{}', '20261110220000'),
 ('function', 'security.aer_read_now_v1', 'Layer 2', 'Runs the on-demand entry-requirements plan once at a time through the existing read, read-again and replay functions; records one admin_control_events row', 'active', '{}', '20261110220000'),
 ('function', 'security.aer_read_now_plan_v1', 'Layer 2', 'What one click of Read / refresh entry requirements now would do, or exactly why not (read only)', 'active', '{}', '20261110220000'),
 ('function', 'security.aer_read_now_class_v1', 'Layer 2', 'The kind of evidence behind a read-now outcome, as a screen label (no source found, source found not read, tried not found, technical failure, budget hold, human review)', 'active', '{}', '20261110220000'),
 ('function', 'security.aer_read_now_source_v1', 'Layer 2', 'The source that was examined for a provider or course, as the existing readers recorded it (read only)', 'active', '{}', '20261110220000'),
 ('function', 'security.aer_read_now_status_v1', 'Layer 2', 'The six-stage timeline of a provider or course for entry requirements (read only)', 'active', '{}', '20261110220000'),
 ('function', 'security.aer_pending_packets_v1', 'Layer 2', 'Waiting entry-requirement Layer 4 items with their packet state from the stored gate (read only)', 'active', '{}', '20261110220000'),
 ('function', 'security.aer_packet_rows_v1', 'Layer 2', 'Per proposed row: which of country, qualification, grade, scale, applicability, source page and year are stated (read only)', 'active', '{}', '20261110220000'),
 ('function', 'security.aer_packet_facts_v1', 'Layer 2', 'The facts check of one waiting entry item for its reviewer (read only)', 'active', '{}', '20261110220000'),
 ('function', 'security.aer_course_population_v1(uuid)', 'Layer 2', 'The scheduled entry reading''s eligibility rules for one provider (the no-argument form delegates here)', 'active', '{}', '20261110220000')
on conflict do nothing;

do $post$ begin
  if position('aer_course_population_v1(null::uuid)' in (select p.prosrc from pg_proc p where p.oid = 'security.aer_course_population_v1()'::regprocedure)) = 0 then raise exception 'post-check: the no-argument population does not delegate'; end if;
  if position('reviewer' in (select p.prosrc from pg_proc p where p.oid = 'security.data_delivery_aer_v1()'::regprocedure)) = 0 then raise exception 'post-check: the AER Data Delivery has no reviewer key'; end if;
  if position('aer_packet_facts_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.layer4_aer_review_detail_v1(text)'::regprocedure)) = 0 then raise exception 'post-check: the reviewer detail has no facts section'; end if;
  if position('v_sw_all' in (select p.prosrc from pg_proc p where p.oid = 'security.data_delivery_v1()'::regprocedure)) = 0 then raise exception 'post-check: Data Delivery does not derive the recovery switch state from every switch'; end if;
  if position('data_delivery_aer_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.data_delivery_v1()'::regprocedure)) = 0 or position('data_delivery_pdesc_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.data_delivery_v1()'::regprocedure)) = 0 then raise exception 'post-check: another stream key was lost'; end if;
end $post$;
