-- CF-247 AER reviewer-ready queue, technical routing and recovery pilots (Platform Admin direction 4 Nov 2026 10:00 §3 and §4, admin
-- docs/platform/2026-11-04-autonomous-admission-throughput-direction-1000.md; investigation 2026-11-04-aer-throughput-investigation.md §7).
-- Why (live, read only, 4 Nov 2026 11:09-11:19 AEDT):
--   * 605 AER items wait. By the gate itself (11:16): 169 complete course reads, 25 course reads held only for rows a person leaves out,
--     162 cut at the row limit, 45 on a shared page, 163 dropping printed minimums; 2 matrix runs complete and 39 held by D-R3. The "23 ready
--     matrix runs" were readiness's judgement_ready label on runs that were never gated; 21 of the 39 held runs are ANU's.
--   * Readiness (v2.15.465) gates never-gated entry items first: 60 gates since 09:37 (42 course reads moved: 5 complete, 21 dropped minimums,
--     11 row limit, 4 row level, 1 shared page); 471 course reads and 3 matrix runs are still never gated (about 12 hours at layer4.gate_batch 20).
--   * The Inbox shows an AER card's facts and HAR's recovery choices, but not what a reviewer needs to decide in order: the course, its
--     qualification and country, the rows and their quotations, the active rows and locks, the checks, the recommended decision and what it does.
--     Ownership with the ChatGPT browser reviewer (pipeline.layer4_review_owners) is not shown or claimable for AER.
--   * Held reads have no route: technical recovery records them, Human-assisted recovery raises nothing for course reads (lane aer_item has no
--     generator), and v2.15.465's E13 recovery would re-read an item whose corrected read was already refused on the same stored copy.
-- What (no new screen; the Inbox hook register of v2.15.462 and the intervention contract of v2.15.463):
--   1. security.aer_route_v1(field, gate): the class and route of an AER item from its gate result: review (complete), review_except (rows a
--      person leaves out), row_limit or source_is_matrix (a provider row boundary or the page mapped as the provider's matrix: authority),
--      identity (shared page: aer_course_identity), missing_scale, quote_association, low_confidence (dropped minimums: E13 recovery from the
--      stored copy, else aer_read_rows_missing), matrix_source (D-R3 dropped rows or unscaled values: Human-assisted recovery's provider-level
--      aer_read_held), matrix_except (rows left out), awaiting_gate (never gated).
--   2. security.aer_review_packet_v1(item): one item's review packet: provider, course, qualification, country, audiences, stored evidence and
--      its quotations, proposed rows, active rows, manual locks, the completeness gate (the stored readiness result while it is current, else
--      one live gate for this item only), conflicts, route, recommended existing decision, the consequences of approval and rejection, the
--      open owner of the university, and the item's place in its university's reviewer-ready queue (from stored gate classes, never a gate per row).
--   3. security.layer4_aer_review_detail_v1(ref): the AER card detail: the packet's sections, then Human-assisted recovery's detail and actions
--      unchanged (called, not edited; isolated). The aer_review extend hook reads it (pipeline.layer4_inbox_kind_hooks.detail_fn).
--   4. public.admin_layer4_aer_queue(args) (Pipeline Operator and above, read only): universities with reviewer-ready AER items (followed
--      universities first) and one university's ready items in order, with the owner; security.layer4_aer_owner_claim_v1 records a claim in
--      pipeline.layer4_review_owners (refused while another owner holds the university). Decisions stay the Inbox's own, one item and one audit
--      event each; nothing approves in bulk and nothing here decides.
--   5. security.har_aer_item_generate_v1(limit), registered as lane aer_item's generator (switch har.generate_aer_item_on): one deduplicated
--      intervention per held course read that no automatic remedy can fix: identity (aer_course_identity) for shared pages; aer_read_rows_missing
--      for dropped minimums with no stored copy of the same page, or whose corrected read was refused on the same stored copy, or out of tries.
--      Fair by university (har.generate_per_provider_max), bounded by batch.har_generate and har.open_max_per_lane. Row-limit and matrix holds are
--      not raised here (authority; Human-assisted recovery's provider-level aer_read_held). Valid input resumes the read through v2.15.463.
--   6. E13 recovery pilot (security.aer_e13_recover_v1, md5-guarded edit): only universities listed in aer.e13_recover_providers; at most
--      aer.e13_recover_total_max requests over the pilot; never an item whose corrected read was refused on the same stored copy (the reader is
--      deterministic on unchanged evidence). security.aer_e13_pilot_report_v1() measures replacement yield.
--   7. security.aer_fair_projection_v1(): what wc.aer_fair_on would do now, by university, from stored readiness (read only).
--   8. RMIT settlement (Platform Admin direction 4 Nov 2026 12:16, admin docs/platform/2026-11-04-rmit-aer-layer4-settlement-direction-1216.md):
--      security.aer_settlement_v1(provider): every waiting AER item in one of four classes from stored records only (ready; recoverable: an
--      automatic step remains; needs_input; stale), with the reason and the next action. A held read whose corrected reads were refused for the
--      row limit on the same copy (they kept every printed requirement: value.rows_read) is route row_limit_stored: it waits for a row boundary,
--      never another re-read and never a rows request (a person's rows would only resume the same refused read; the generator skips it).
--      The queue returns one university's ready items as Inbox items, so the Inbox shows them first and decides them with its own decide action;
--      security.layer4_aer_university_summary_v1 gives the Inbox's university summary (pending, review-ready, technically held, human input
--      required, open interventions, admitted, unresolved) through public.admin_layer4_aer_queue({summary_provider_id}); the card's detail opens
--      with a readable summary (class, failure, next action). security.aer_progress_counts_v1(since, provider) counts submitted, saved,
--      admitted and published AER decisions for the execution register. src/Layer4Inbox.jsx: the summary line, Ready to decide / All waiting,
--      and hook detail rendered as text (a recovery case as a sentence with an expandable list of related items linked to their cards).
-- Activation: ON (records, presents, asks people; admits and spends nothing): 1-5, 7, 8. OFF: aer.e13_recover_on (unchanged: off).
-- Settings (G2): aer.e13_recover_providers, aer.e13_recover_total_max, aer.row_limit_matrix_rows, aer.review_packet_rows, har.generate_aer_item_on.
-- Before (live, 4 Nov 2026 11:18 AEDT) -> after:
--   security.aer_e13_recover_v1(boolean) 90f80d59db94e29aab3fc520d1c99be6 -> 1bd8be8be44d5cd6e25a41a337b43f61
--   Called, not edited (checked): security.layer4_intervention_raise_v1(jsonb) 8fcabf1137cf126158c260759ac9f9aa, security.aer_e13_class_v1(jsonb)
--   be023e0e23074cbdd8ed370b3fc7c000; security.layer4_aer_recovery_detail_v1(text) is called by name only (hotfix v2.15.466 replaces it).
--   The Inbox functions are not edited: security.layer4_inbox_items_v1() 2fa8b921, public.admin_layer4_inbox(text,jsonb) 29705b99.
-- Replaces: the aer_review extend hook's detail (security.layer4_aer_recovery_detail_v1, now called by security.layer4_aer_review_detail_v1)
-- Retires: nothing
-- Nothing is dropped or deleted. The 600 limit, E13, D-R3 and the consumer API are unchanged.

-- 0 the definitions this change calls or edits, as read live ---------------------------------------------------------------------------------
do $g$
declare r record;
begin
  for r in select * from (values ('security.layer4_intervention_raise_v1(jsonb)', '8fcabf1137cf126158c260759ac9f9aa'),
                                 ('security.aer_e13_class_v1(jsonb)', 'be023e0e23074cbdd8ed370b3fc7c000')) v(sig, m) loop
    if to_regprocedure(r.sig) is null then raise exception 'live % is missing', r.sig; end if;
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then
      raise exception 'live % differs from the definition this change was written against (md5 %)', r.sig, md5(pg_get_functiondef(r.sig::regprocedure)); end if;
  end loop;
  for r in select * from (values ('security.layer4_aer_recovery_detail_v1(text)'), ('security.course_entry_gate_v1(uuid,uuid[])'), ('security.work_item_report_v1(text,text,text,text,jsonb)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'live % is missing', r.sig; end if;
  end loop;
  if not exists (select 1 from pipeline.layer4_inbox_kind_hooks h where h.kind = 'aer_review' and h.mode = 'extend') then
    raise exception 'the aer_review extend hook (v2.15.462/463) is missing'; end if;
  if not exists (select 1 from pipeline.layer4_intervention_handlers h where h.lane = 'aer_item') then
    raise exception 'the aer_item intervention lane (v2.15.463) is missing'; end if;
end $g$;

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 1 settings (G2) ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.e13_recover_providers', 'Entry requirements: universities in the E13 recovery pilot',
  'E13 recovery re-reads held course reads only of these universities (provider ids). Empty: none. The pilot itself runs only while aer.e13_recover_on is 1.',
  'list', '["6f5cb7f7-7c70-4c06-970f-f368c3a786e2", "551383f9-7732-4588-a843-dd2b97c13f6f", "fa0e0d13-838a-42ff-b6a3-9cea84bd80b2", "fec52f92-a8a3-4de8-a862-06f355e4e2f7", "030992c3-72c6-452d-8a3b-10ceb0fd77f2", "f02d9d9b-0eb2-4f0e-8215-27a36ae63aa6", "c5c5d225-3d4c-4e41-8275-78eddd261073", "fe6af182-f5ca-4a3c-bfb4-b0773ff1b113", "8e1adb6c-e069-43db-9584-bd054255e702", "9109fe0c-9f44-4e2d-a136-eb00dec24701"]'::jsonb,
  null, null, 'universities', 1464, 'Entry requirements', 'security.aer_e13_recover_v1', 'Direction 4 Nov 2026 10:00 §4: a bounded pilot (the ten universities of mandate 08:16 §8)'),
 ('pipeline', 'aer.e13_recover_total_max', 'Entry requirements: corrected reads over the E13 recovery pilot',
  'At most this many corrected reads are asked by E13 recovery in all (every request it ever made counts). Raise it to extend the pilot.',
  'number', to_jsonb(40), 0, 1000, 'reads', 1465, 'Entry requirements', 'security.aer_e13_recover_v1', 'Direction 4 Nov 2026 10:00 §4: a bounded, reversible pilot'),
 ('pipeline', 'aer.row_limit_matrix_rows', 'Entry requirements: rows cut that mark a page as a qualification table',
  'A course read cut at the row limit with at least this many rows cut is routed as a page to map as the university''s entry matrix source, not as a row boundary to raise.',
  'number', to_jsonb(30), 6, 500, 'rows', 1466, 'Entry requirements', 'security.aer_route_v1', 'Direction 4 Nov 2026 10:00 §4 (QUT: a median of 68 rows a page, country tables)'),
 ('pipeline', 'aer.review_packet_rows', 'Entry requirements: rows shown on a review card',
  'At most this many proposed rows, active rows and quotations are listed on one AER review card (the counts are always exact).',
  'number', to_jsonb(30), 5, 200, 'rows', 1467, 'Entry requirements', 'security.aer_review_packet_v1', 'Direction 4 Nov 2026 10:00 §3 (the reviewer interface)'),
 ('pipeline', 'har.generate_aer_item_on', 'Human-assisted recovery: raise interventions for held AER reads',
  'On (1): the layer4-interventions job raises one intervention for each held course read no automatic remedy can fix (shared page: confirm the course; dropped minimums with no usable stored copy or already refused on it: enter the rows). Off (0): none.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1503, 'Human-assisted recovery', 'security.har_aer_item_generate_v1 (job layer4-interventions)',
  'Direction 4 Nov 2026 10:00 §3: "create one deduplicated human-assisted intervention"')
on conflict (toolset_key, key) do nothing;

-- 2 route and review packet -----------------------------------------------------------------------------------------------------------------
create or replace function security.aer_route_v1(p_field text, p_gate jsonb) returns jsonb
language sql stable set search_path to '' as $function$
-- the class and route of a waiting AER item from its gate result (course: security.course_entry_gate_v1; matrix: security.entry_matrix_gate_v1)
  with g as (select p_gate g, security.aer_e13_class_v1(p_gate) c,
                    coalesce((select string_agg(x, ' ') from jsonb_array_elements_text(coalesce(p_gate->'reasons', '[]'::jsonb)) x), '') rs,
                    coalesce((select array_agg(distinct d->>'reason') from jsonb_array_elements(coalesce(p_gate->'drops_uncovered', '[]'::jsonb)) d), '{}') dr)
  select case
    when p_gate is null then jsonb_build_object('class', 'unchecked', 'route', 'awaiting_gate', 'person', false,
           'remedy', 'job layer4-readiness gates it (never-gated items first, layer4.gate_batch a run)')
    when p_field <> 'course_entry_first_read' then
      case when coalesce((g->>'complete')::boolean, false) then jsonb_build_object('class', 'complete', 'route', 'review', 'person', true, 'remedy', 'a person decides (Approve or Reject the run)')
           when rs ~* '(dropped [0-9]+ published row|no printed scale|without a scale|not printed in its quote|column left out)' then
             jsonb_build_object('class', 'matrix_held', 'route', 'matrix_source', 'person', true,
               'remedy', 'the source''s missing rows, scales or country mapping: Human-assisted recovery''s provider-level intervention (aer_read_held), then the matrix re-read')
           else jsonb_build_object('class', 'matrix_held', 'route', 'matrix_except', 'person', true, 'remedy', 'a person leaves out the rows the check names (Approve except), or rejects the run') end
    when c = 'complete' then jsonb_build_object('class', c, 'route', 'review', 'person', true, 'remedy', 'a person decides (Approve all rows or Reject the read)')
    when c = 'row_level' then jsonb_build_object('class', c, 'route', 'review_except', 'person', true, 'remedy', 'a person leaves out the named rows (Approve except) or rejects the read')
    when c = 'row_limit' and coalesce((g->>'rows_cut')::int, 0) >= security.pipeline_num_v1('aer.row_limit_matrix_rows', 30) then
      jsonb_build_object('class', c, 'route', 'source_is_matrix', 'person', false, 'authority', true,
        'remedy', 'the page is a qualification table: map it as the university''s entry matrix source (identity and source mapping), not a higher row limit')
    when c = 'row_limit' then jsonb_build_object('class', c, 'route', 'row_limit', 'person', false, 'authority', true,
        'remedy', 'a row boundary for the university (entry.max_rows_by_provider, Platform Admin), then a corrected read; a re-read with the same limit cuts the same rows')
    when c = 'shared_page' then jsonb_build_object('class', c, 'route', 'identity', 'person', true,
        'remedy', 'confirm which programme the stored page belongs to (aer_course_identity); never an extraction retry')
    when c = 'drops_uncovered' then jsonb_build_object('class', c,
        'route', case when 'score_without_basis' = any (dr) then 'missing_scale' when 'quote_not_on_page' = any (dr) then 'quote_association' else 'low_confidence' end,
        'person', false, 'reasons', to_jsonb(dr),
        'remedy', 'a corrected read from the stored copy (E13 recovery, pilot) when it has not been refused on that copy; otherwise the dropped rows with their quotations and scale from a person (aer_read_rows_missing)')
    else jsonb_build_object('class', c, 'route', 'unknown', 'person', true, 'remedy', 'see the gate reasons') end
  from g
$function$;
revoke all on function security.aer_route_v1(text, jsonb) from public, anon, authenticated;

create or replace function security.aer_review_packet_v1(p_item uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 direction 10:00 §3: everything a reviewer needs to decide one AER item, from existing records. The gate is the stored readiness
-- result while it is current (layer4.readiness_recheck_minutes), else one live gate of this item only; the queue position is read from stored
-- gate classes (never a gate per row). Read only.
declare r pipeline.layer4_review_items; x pipeline.layer4_item_readiness; g jsonb; v_gsrc text; v_pid uuid; v_course record; v_ev record; v_rt jsonb;
        v_n int := security.pipeline_num_v1('aer.review_packet_rows', 30)::int; v_prop jsonb; v_act jsonb; v_nprop int; v_nact int; v_locks jsonb;
        v_rec text; v_ex jsonb; v_aud jsonb; v_owner jsonb; v_pos jsonb; v_cons jsonb; v_run record; v_conf jsonb; v_d4 boolean; v_set jsonb;
begin
  select * into r from pipeline.layer4_review_items where id = p_item;
  if r.id is null or r.field_code not in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change') then return null; end if;
  select * into x from pipeline.layer4_item_readiness where item_id = p_item;
  -- both kinds' records exist before either is read (a record not yet assigned cannot be referenced)
  select null::uuid id, null::uuid source_id, null::int rows_admitted, null::int rows_dropped, null::text url into v_run;
  select null::uuid id, null::uuid provider_id, null::text title, null::text course_code, null::text publication_status, null::text level, null::text country into v_course;
  if x.gate_checked_at is not null and x.gate_checked_at > now() - make_interval(mins => security.pipeline_num_v1('layer4.readiness_recheck_minutes', 120)::int) then
    g := x.gate; v_gsrc := 'stored (job layer4-readiness, ' || to_char(x.gate_checked_at at time zone 'Australia/Melbourne', 'DD Mon HH24:MI') || ')';
  elsif r.field_code = 'course_entry_first_read' then
    g := security.course_entry_gate_v1(p_item); v_gsrc := 'checked now';
  else
    select m.id into v_run from pipeline.entry_matrix_runs m where m.review_item_id = p_item order by m.created_at desc limit 1;
    g := case when v_run.id is not null then security.entry_matrix_gate_v1(v_run.id, '{}'::uuid[]) end; v_gsrc := 'checked now';
  end if;
  v_rt := security.aer_route_v1(r.field_code, g);
  if r.field_code = 'course_entry_first_read' then
    select c.id, c.provider_id, coalesce(c.display_title, c.canonical_title) title, c.course_code, c.publication_status, sl.name level, k.iso_alpha2 country
      into v_course
      from catalogue.courses c left join ref.study_levels sl on sl.id = c.study_level_id
      left join catalogue.providers p on p.id = c.provider_id left join ref.countries k on k.id = p.country_id
     where c.id = r.entity_id;
    v_pid := v_course.provider_id;
    select count(*), coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'kind', z.kind, 'audience', z.audience, 'min_grade', z.min_grade, 'min_value', z.min_value,
             'scale', z.grade_scale, 'min_score', z.min_entry_score, 'basis', z.min_entry_score_basis, 'quote', z.quote, 'confidence', z.confidence) order by z.kind, z.id)
             filter (where z.n <= v_n), '[]'::jsonb)
      into v_nprop, v_prop
      from (select q.*, row_number() over (order by q.kind, q.id) n from catalogue.course_entry_requirements q
             where q.provenance->>'review_item_id' = p_item::text and q.status = 'proposed') z;
    select count(*), coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'kind', z.kind, 'audience', z.audience, 'min_score', z.min_entry_score, 'quote', z.quote,
             'reader', z.provenance->>'reader') order by z.kind, z.id) filter (where z.n <= v_n), '[]'::jsonb)
      into v_nact, v_act
      from (select q.*, row_number() over (order by q.kind, q.id) n from catalogue.course_entry_requirements q where q.course_id = r.entity_id and q.status = 'active') z;
    v_d4 := exists (select 1 from catalogue.course_entry_requirements q where q.course_id = r.entity_id and q.status = 'active' and q.provenance->>'reader' = 'enrich_ai');
    select coalesce(jsonb_agg(distinct q.audience), '[]'::jsonb) into v_aud from catalogue.course_entry_requirements q
     where q.provenance->>'review_item_id' = p_item::text and q.status = 'proposed';
    select coalesce(jsonb_agg(jsonb_build_object('field', l.field, 'mode', l.mode, 'since', l.set_at)), '[]'::jsonb) into v_locks
      from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = r.entity_id
       and l.field in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.supersede_lock_fields'), '["entry_requirements"]'::jsonb)));
    v_ex := (select coalesce(jsonb_agg(distinct e), '[]'::jsonb) from (
               select o->>'id' e from jsonb_array_elements(coalesce(g->'other_programme', '[]'::jsonb)) o
               union all select o->>'id' from jsonb_array_elements(coalesce(g->'not_requirement', '[]'::jsonb)) o
               union all select o->>'id' from jsonb_array_elements(coalesce(g->'audience', '[]'::jsonb)) o) z where e is not null);
    v_conf := jsonb_strip_nulls(jsonb_build_object(
      'rows about another programme', nullif(jsonb_array_length(coalesce(g->'other_programme', '[]'::jsonb)), 0),
      'rows that are not entry requirements', nullif(jsonb_array_length(coalesce(g->'not_requirement', '[]'::jsonb)), 0),
      'domestic rows stored for everyone', nullif(jsonb_array_length(coalesce(g->'audience', '[]'::jsonb)), 0),
      'active rows this approval replaces', nullif(case when v_d4 then (select count(*) from catalogue.course_entry_requirements q where q.course_id = r.entity_id and q.status = 'active' and q.provenance->>'reader' = 'enrich_ai') end, 0),
      'manual locks', nullif(jsonb_array_length(v_locks), 0)));
    v_rec := case
      when v_rt->>'route' = 'review' and jsonb_array_length(v_locks) > 0 then 'Reject the read or leave it: the course has a manual lock on its entry requirements'
      when v_rt->>'route' = 'review' then 'Approve all rows (every check passes)'
      when v_rt->>'route' = 'review_except' and v_d4 then 'Reject the read: Approve except is held (D4) while the course has active entry rows, and some waiting rows must be left out'
      when v_rt->>'route' = 'review_except' then 'Approve except: leave out ' || jsonb_array_length(v_ex) || ' row(s) ' || v_ex::text
      else 'Do not approve: technical recovery (' || (v_rt->>'route') || ')' end;
    v_cons := jsonb_build_object(
      'approve', case when v_rt->>'route' in ('review', 'review_except') then
        format('%s waiting row(s) become active%s; %s active row(s) from earlier reads are superseded; the course''s entry requirements then show on the website (public.website_v2_course "entry")%s',
               v_nprop - case when v_rt->>'route' = 'review_except' then jsonb_array_length(v_ex) else 0 end,
               case when v_rt->>'route' = 'review_except' then ' and ' || jsonb_array_length(v_ex) || ' are kept inactive' else '' end,
               case when v_d4 then (select count(*) from catalogue.course_entry_requirements q where q.course_id = r.entity_id and q.status = 'active' and q.provenance->>'reader' = 'enrich_ai') else 0 end,
               case when coalesce(v_course.publication_status, '') <> 'published' then ' once the course is published (it is ' || coalesce(v_course.publication_status, 'unknown') || ')' else '' end)
        else 'refused: the completeness gate (E13) holds an incomplete read; nothing would change' end,
      'reject', format('%s waiting row(s) are quarantined (inactive); the read is closed as not admitted; the course can be read again after aer.schedule_retry_days (%s days)',
               v_nprop, security.pipeline_num_v1('aer.schedule_retry_days', 30)));
  else
    v_pid := r.entity_id;
    select m.id, m.source_id, m.rows_admitted, m.rows_dropped, s.url into v_run from pipeline.entry_matrix_runs m left join pipeline.entry_matrix_sources s on s.id = m.source_id
     where m.review_item_id = p_item order by m.created_at desc limit 1;
    select count(*), coalesce(jsonb_agg(jsonb_build_object('country', z.country_code, 'level', z.level_label, 'qualification', z.qualification_name, 'min_grade', z.min_grade,
             'scale', z.grade_scale, 'audience', z.audience, 'quote', z.quote) order by z.country_code, z.id) filter (where z.n <= v_n), '[]'::jsonb)
      into v_nprop, v_prop
      from (select q.*, row_number() over (order by q.country_code, q.id) n from catalogue.provider_entry_matrix q where q.run_id = v_run.id and q.status = 'proposed') z;
    select count(*) into v_nact from catalogue.provider_entry_matrix q where q.provider_id = v_pid and q.status = 'active';
    select coalesce(jsonb_agg(distinct q.audience), '[]'::jsonb) into v_aud from catalogue.provider_entry_matrix q where q.run_id = v_run.id and q.status = 'proposed';
    v_locks := '[]'::jsonb; v_act := '[]'::jsonb; v_conf := '{}'::jsonb;
    v_rec := case v_rt->>'route' when 'review' then 'Approve the run (every check passes)'
                                 when 'matrix_except' then 'Approve except the rows the check names, or reject the run'
                                 else 'Do not approve: technical recovery (' || (v_rt->>'route') || ')' end;
    v_cons := jsonb_build_object('approve', case when v_rt->>'route' in ('review', 'matrix_except') then v_nprop || ' row(s) become the university''s active entry matrix rows (public.website_v2_provider "entry_matrix")'
                                                 else 'refused: the completeness gate (D-R3) holds an incomplete run; nothing would change' end,
                                 'reject', v_nprop || ' row(s) are not admitted; the source is read again when it changes or is due');
  end if;
  select ev.id, ev.captured_at, ev.source_url into v_ev from pipeline.evidence_artifacts ev where ev.id = r.evidence_id;
  select coalesce(jsonb_agg(jsonb_build_object('owner', o.owner, 'scope', o.scope, 'since', o.since)), '[]'::jsonb) into v_owner
    from pipeline.layer4_review_owners o where o.provider_id = v_pid and o.field_code = r.field_code and o.closed_at is null;
  -- the university's settlement (stored records only, never a gate per row): this item's class and its place among the ready items
  with st as (select * from security.aer_settlement_v1(v_pid)),
       o as (select st.item_id, row_number() over (order by st.created_at, st.item_id) n, count(*) over () t from st where st.settlement = 'ready' and st.field_code = r.field_code)
  select (select jsonb_build_object('settlement', st.settlement, 'why', st.why, 'next_action', st.next_action, 'route', st.route, 'tries', st.tries,
                                    'last_refusal', st.last_refusal, 'rows_read', st.rows_read) from st where st.item_id = p_item),
         jsonb_build_object('ready_at_university', coalesce((select max(t) from o), 0), 'position', (select n from o where o.item_id = p_item),
           'next_ready', (select o2.item_id from o o2 where o2.n = coalesce((select n from o where o.item_id = p_item), 0) + 1))
    into v_set, v_pos;
  return jsonb_build_object('item', p_item, 'field_code', r.field_code, 'provider_id', v_pid,
    'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_pid),
    'course', case when r.field_code = 'course_entry_first_read' then jsonb_build_object('id', v_course.id, 'title', v_course.title, 'code', v_course.course_code,
                   'qualification', v_course.level, 'country', v_course.country, 'publication', v_course.publication_status) end,
    'source', case when r.field_code <> 'course_entry_first_read' then jsonb_build_object('run_id', v_run.id, 'url', v_run.url, 'rows_dropped', v_run.rows_dropped) end,
    'audiences', v_aud,
    'evidence', jsonb_build_object('evidence_id', r.evidence_id, 'captured_at', v_ev.captured_at, 'url', coalesce(v_ev.source_url, r.proposed_value->>'url')),
    'proposed', jsonb_build_object('count', v_nprop, 'rows', v_prop), 'active', jsonb_build_object('count', v_nact, 'rows', v_act), 'locks', v_locks,
    'gate', jsonb_build_object('source', v_gsrc, 'complete', coalesce((g->>'complete')::boolean, false), 'reasons', coalesce(g->'reasons', '[]'::jsonb)),
    'conflicts', v_conf, 'route', v_rt, 'exclude_row_ids', coalesce(v_ex, '[]'::jsonb), 'recommended', v_rec, 'consequences', v_cons,
    'owner', v_owner, 'queue', v_pos, 'settlement', v_set);
end $function$;
revoke all on function security.aer_review_packet_v1(uuid) from public, anon, authenticated;

create or replace function security.layer4_aer_review_detail_v1(p_ref text) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- the AER card detail (extend hook; paging contract shape {sections, actions}): the review packet first, then Human-assisted recovery's own
-- detail and actions unchanged (called by name; a failure there leaves the packet). Decisions stay the Inbox's (one item, one audit event).
declare p jsonb; h jsonb; v_sec jsonb;
begin
  p := security.aer_review_packet_v1(p_ref::uuid);
  if p is null then return jsonb_build_object('sections', '[]'::jsonb, 'actions', '[]'::jsonb); end if;
  begin
    h := security.layer4_aer_recovery_detail_v1(p_ref);
  exception when others then
    h := jsonb_build_object('sections', jsonb_build_array(jsonb_build_object('key', 'recovery', 'title', 'Recovery', 'body', jsonb_build_object('Not available', left(sqlerrm, 200)))),
                            'actions', '[]'::jsonb);
  end;
  v_sec := jsonb_build_array(
    -- direction 12:16 §7: a readable summary first: what this item is, why, and the next action
    jsonb_build_object('key', 'summary', 'title', 'Summary', 'body', jsonb_strip_nulls(jsonb_build_object(
      'Class', case p->'settlement'->>'settlement' when 'ready' then 'Ready for a decision' when 'recoverable' then 'Technically held: an automatic recovery remains'
                                                 when 'needs_input' then 'Needs evidence, input or a decision' when 'stale' then 'Stale: no longer a valid read' end,
      'Failure', case when p->'settlement'->>'settlement' <> 'ready' then p->'settlement'->>'why' end,
      'Next action', p->'settlement'->>'next_action',
      'Corrected reads so far', nullif((p->'settlement'->>'tries')::int, 0)))),
    jsonb_build_object('key', 'review', 'title', 'Review', 'body', jsonb_strip_nulls(jsonb_build_object(
      'University', p->>'provider', 'Course', p->'course'->>'title', 'Course code', p->'course'->>'code', 'Qualification', p->'course'->>'qualification',
      'Country', p->'course'->>'country', 'Source', p->'source'->>'url', 'Audience', p->'audiences', 'Stored copy', p->'evidence',
      'Recommended decision', p->>'recommended', 'If approved', p->'consequences'->>'approve', 'If rejected', p->'consequences'->>'reject',
      'Owner', case when jsonb_array_length(p->'owner') = 0 then 'no one has claimed this university and kind' else (p->'owner')::text end,
      'Queue', case when (p->'queue'->>'position') is not null then (p->'queue'->>'position') || ' of ' || (p->'queue'->>'ready_at_university') || ' ready at this university'
                    else 'not reviewer-ready: ' || (p->'route'->>'route') || ' (' || (p->'queue'->>'ready_at_university') || ' ready at this university)' end,
      'Next ready item', p->'queue'->>'next_ready'))),
    jsonb_build_object('key', 'checks', 'title', 'Completeness and conflicts', 'body', jsonb_strip_nulls(jsonb_build_object(
      'Gate', case when (p->'gate'->>'complete')::boolean then 'complete' else 'held' end, 'Checked', p->'gate'->>'source', 'Reasons', p->'gate'->'reasons',
      'Conflicts', nullif(p->'conflicts', '{}'::jsonb), 'Rows to leave out', nullif(p->'exclude_row_ids', '[]'::jsonb),
      'Route', p->'route'->>'route', 'Remedy', p->'route'->>'remedy'))),
    jsonb_build_object('key', 'rows', 'title', 'Proposed rows (' || (p->'proposed'->>'count') || ')', 'body', p->'proposed'->'rows'),
    jsonb_build_object('key', 'active', 'title', 'Active rows (' || (p->'active'->>'count') || ')', 'body', p->'active'->'rows'));
  if jsonb_array_length(p->'locks') > 0 then v_sec := v_sec || jsonb_build_array(jsonb_build_object('key', 'locks', 'title', 'Manual locks', 'body', p->'locks')); end if;
  return jsonb_build_object('sections', v_sec || coalesce(h->'sections', '[]'::jsonb), 'actions', coalesce(h->'actions', '[]'::jsonb), 'packet', p);
end $function$;
revoke all on function security.layer4_aer_review_detail_v1(text) from public, anon, authenticated;

update pipeline.layer4_inbox_kind_hooks set detail_fn = 'security.layer4_aer_review_detail_v1(text)',
       note = coalesce(note, '') || ' | 4 Nov 2026 (direction 10:00 §3): detail is the review packet then the recovery detail (security.layer4_aer_review_detail_v1)'
 where kind = 'aer_review' and mode = 'extend' and detail_fn = 'security.layer4_aer_recovery_detail_v1(text)';

-- 3 settlement classes, the reviewer-ready queue, the university summary and ownership (direction 12:16 §1-§2, §5, §8) -------------------
create or replace function security.aer_settlement_v1(p_provider uuid) returns table(item_id uuid, field_code text, created_at timestamptz, provider_id uuid, cls text,
  route text, settlement text, why text, next_action text, tries int, last_refusal text, rows_read int)
language sql stable security definer set search_path to '' as $function$
-- CF-247 direction 12:16 §2-§3: each waiting AER item of a university (all universities when null) in one of four settlement classes, from stored
-- records only (the readiness gate result, the corrected-read history, locks, the bound page; never a gate per row):
--   ready        a person can decide it now (complete, or rows to leave out)
--   recoverable  technically held with an automatic recovery that has not yet run on this evidence (an untried corrected read from the stored
--                copy of the same page), or not yet gated (job layer4-readiness)
--   needs_input  a person or the Platform Admin must supply something: the course a shared page belongs to, the dropped rows after a refused
--                corrected read on unchanged evidence (a deterministic repeat), a row boundary (row limit; the stored rows read need no new AI
--                read once it is set), the matrix source, or a manual lock
--   stale        no longer a valid read of the course: the course is inactive or its bound page is not the page read
  with b as (
    select i.id, i.field_code, i.created_at, i.entity_type, i.entity_id, coalesce(c.provider_id, case when i.entity_type = 'provider' then i.entity_id end) pid, y.gate,
           c.lifecycle_status, pg.url pg_url, pg.evidence_id pg_ev, i.proposed_value->>'url' read_url,
           exists (select 1 from pipeline.manual_locks l where i.entity_type = 'course' and l.entity = 'course' and l.entity_id = i.entity_id and l.field = 'entry_requirements') locked,
           (select count(*)::int from pipeline.aer_read_supersessions s where s.old_item_id = i.id) tries,
           (select s.outcome from pipeline.aer_read_supersessions s where s.old_item_id = i.id and s.state = 'refused' order by s.requested_at desc limit 1) refusal,
           (select jsonb_array_length(coalesce(fe.value->'rows_read', '[]'::jsonb))::int from pipeline.aer_read_supersessions s join pipeline.field_enrich_items fe on fe.id = s.enrich_item_id
             where s.old_item_id = i.id order by s.requested_at desc limit 1) rows_read
      from pipeline.layer4_review_items i
      left join pipeline.layer4_item_readiness y on y.item_id = i.id
      left join catalogue.courses c on i.entity_type = 'course' and c.id = i.entity_id
      left join pipeline.coverage_course_pages pg on i.entity_type = 'course' and pg.course_id = i.entity_id
     where i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change')
       and (p_provider is null or coalesce(c.provider_id, case when i.entity_type = 'provider' then i.entity_id end) = p_provider)),
  r as (select b.*, security.aer_route_v1(b.field_code, b.gate) rt from b)
  select r.id, r.field_code, r.created_at, r.pid, coalesce(r.rt->>'class', 'unchecked'),
         case when r.rt->>'class' = 'drops_uncovered' and r.refusal ilike '%row limit%' then 'row_limit_stored'
              when r.rt->>'class' = 'drops_uncovered' and r.refusal ilike '%proof does not admit%' then 'identity' else r.rt->>'route' end,
         z.settlement, z.why, z.next_action, r.tries, r.refusal, r.rows_read
    from r cross join lateral (select * from (values (
      case when r.entity_type = 'course' and (coalesce(r.lifecycle_status, 'active') <> 'active' or r.pg_url is distinct from r.read_url) then 'stale'
           when r.gate is null then 'recoverable'
           when r.locked then 'needs_input'
           when r.rt->>'route' in ('review', 'review_except', 'matrix_except') then 'ready'
           when r.rt->>'class' = 'drops_uncovered' and r.tries = 0 and r.pg_ev is not null then 'recoverable'
           else 'needs_input' end,
      case when r.entity_type = 'course' and coalesce(r.lifecycle_status, 'active') <> 'active' then 'the course is no longer active'
           when r.entity_type = 'course' and r.pg_url is distinct from r.read_url then 'the course is now bound to another page: a new first read, not a correction'
           when r.gate is null then 'not yet checked by the completeness gate'
           when r.locked then 'the course''s entry requirements are locked by hand'
           when r.rt->>'route' = 'review' then 'every check passes'
           when r.rt->>'route' in ('review_except', 'matrix_except') then 'rows a person leaves out'
           when r.rt->>'class' = 'drops_uncovered' and r.refusal ilike '%row limit%' then 'the corrected read kept every printed requirement (' || coalesce(r.rows_read, 0) || ' rows) but is over the row limit; a re-read gives the same result'
           when r.rt->>'class' = 'drops_uncovered' and r.refusal ilike '%proof does not admit%' then 'the page''s identity proof does not admit entry requirements'
           when r.rt->>'class' = 'drops_uncovered' and r.tries = 0 and r.pg_ev is not null then 'printed requirements were dropped; a corrected read from the stored copy has not been tried'
           when r.rt->>'class' = 'drops_uncovered' and r.pg_ev is null then 'printed requirements were dropped and there is no stored copy to read again'
           when r.rt->>'class' = 'drops_uncovered' then 'the corrected read was refused on the same stored copy (' || coalesce(r.refusal, 'no reason') || '): the reader repeats itself on unchanged evidence'
           else coalesce(r.gate->'reasons'->>0, r.rt->>'remedy') end,
      case when r.entity_type = 'course' and (coalesce(r.lifecycle_status, 'active') <> 'active' or r.pg_url is distinct from r.read_url) then 'Reject the read (it no longer describes the course''s bound page)'
           when r.gate is null then 'job layer4-readiness gates it (never-gated items first)'
           when r.locked then 'leave it, or a Platform Admin lifts the lock'
           when r.rt->>'route' = 'review' then 'decide it in Layer 4: Approve all rows or Reject the read'
           when r.rt->>'route' in ('review_except', 'matrix_except') then 'decide it in Layer 4: Approve except the named rows, or Reject'
           when r.rt->>'class' = 'drops_uncovered' and r.refusal ilike '%row limit%' then 'a row boundary for the university (entry.max_rows_by_provider, Platform Admin); no new re-read until then'
           when r.rt->>'class' = 'drops_uncovered' and r.refusal ilike '%proof does not admit%' then 'confirm the course''s page (aer_course_identity)'
           when r.rt->>'class' = 'drops_uncovered' and r.tries = 0 and r.pg_ev is not null then 'one corrected read from the stored copy (E13 recovery pilot, or Re-read from stored evidence)'
           when r.rt->>'class' = 'drops_uncovered' then 'a person enters the dropped rows with their quotations (aer_read_rows_missing); no further re-read of this copy'
           when r.rt->>'route' in ('row_limit', 'source_is_matrix') then r.rt->>'remedy'
           when r.rt->>'route' = 'identity' then 'confirm which programme the page belongs to (aer_course_identity)'
           else coalesce(r.rt->>'remedy', 'see the gate reasons') end)) v(settlement, why, next_action)) z
$function$;
revoke all on function security.aer_settlement_v1(uuid) from public, anon, authenticated;

create or replace function security.layer4_aer_queue_v1(p_args jsonb) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- reviewer-ready AER items (settlement ready, stored records only) by university: followed universities first (coverage.aer_priority_providers),
-- then the most ready; one university's ready items oldest first, as Inbox items (kind aer_review), so the Inbox shows them first and decides
-- them through its own decide action (one item, one audit event)
  with s as (select * from security.aer_settlement_v1(nullif(p_args->>'provider_id', '')::uuid)),
       r as (select * from s where s.settlement = 'ready'),
       f as (select x::uuid pid, n from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'coverage.aer_priority_providers'), '[]'::jsonb)) with ordinality z(x, n)),
       u as (select r.provider_id pid, count(*) ready, count(*) filter (where r.route <> 'review') except_n, min(r.created_at) oldest from r group by 1),
       own as (select o.provider_id, jsonb_agg(jsonb_build_object('owner', o.owner, 'field_code', o.field_code, 'scope', o.scope)) owners
                 from pipeline.layer4_review_owners o where o.closed_at is null and o.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change') group by 1),
       pg as (select r.* from r where p_args ? 'provider_id' order by r.created_at, r.item_id
               limit security.pipeline_num_v1('layer4.inbox_page_size', 25)::int offset greatest(coalesce((p_args->>'offset')::int, 0), 0))
  select jsonb_build_object(
    'ready', (select count(*) from r), 'by_settlement', (select jsonb_object_agg(z.settlement, z.n) from (select s.settlement, count(*) n from s group by 1) z),
    'universities', coalesce((select jsonb_agg(jsonb_build_object('provider_id', u.pid, 'name', coalesce(p.display_name, p.canonical_name), 'ready', u.ready,
                      'approve_except', u.except_n, 'oldest', u.oldest, 'followed', f.n is not null, 'owners', coalesce(own.owners, '[]'::jsonb))
                      order by f.n nulls last, u.ready desc, coalesce(p.display_name, p.canonical_name))
                 from u left join f on f.pid = u.pid left join own on own.provider_id = u.pid left join catalogue.providers p on p.id = u.pid), '[]'::jsonb),
    'items', case when p_args ? 'provider_id' then coalesce((select jsonb_agg(jsonb_build_object('kind', 'aer_review', 'ref', pg.item_id::text, 'provider_id', pg.provider_id,
                      'provider', coalesce(pv.display_name, pv.canonical_name), 'subject', coalesce(c.display_title, c.canonical_title, 'Entry requirements'),
                      'why', coalesce(nullif(i.escalation_reason, ''), 'Needs a decision'), 'created_at', pg.created_at, 'route', pg.route, 'ready', true,
                      'detail', jsonb_strip_nulls(jsonb_build_object('field_code', pg.field_code, 'course_id', c.id, 'course_code', c.course_code, 'code_label', 'CRICOS',
                                                 'evidence_id', i.evidence_id, 'captured_at', ev.captured_at, 'source_url', ev.source_url)))
                      order by pg.created_at, pg.item_id)
                 from pg join pipeline.layer4_review_items i on i.id = pg.item_id
                 left join catalogue.courses c on i.entity_type = 'course' and c.id = i.entity_id
                 left join catalogue.providers pv on pv.id = pg.provider_id
                 left join pipeline.evidence_artifacts ev on ev.id = i.evidence_id), '[]'::jsonb) end,
    'offset', greatest(coalesce((p_args->>'offset')::int, 0), 0), 'limit', security.pipeline_num_v1('layer4.inbox_page_size', 25)::int)
$function$;
revoke all on function security.layer4_aer_queue_v1(jsonb) from public, anon, authenticated;

create or replace function security.layer4_aer_university_summary_v1(p_provider uuid) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- CF-247 direction 12:16 §8: one university's AER position from stored records: pending, review-ready, technically held (an automatic step
-- remains), human input required (a person or authority must act), open Human input needed items, stale, admitted (courses with active entry rows
-- and active matrix rows) and unresolved (pending less review-ready)
  with s as (select * from security.aer_settlement_v1(p_provider))
  select jsonb_build_object('provider_id', p_provider,
    'pending', (select count(*) from s), 'review_ready', (select count(*) from s where s.settlement = 'ready'),
    'technically_held', (select count(*) from s where s.settlement = 'recoverable'), 'human_input_required', (select count(*) from s where s.settlement = 'needs_input'),
    'stale', (select count(*) from s where s.settlement = 'stale'), 'unresolved', (select count(*) from s where s.settlement <> 'ready'),
    'human_input_open', (select count(*) from pipeline.layer4_interventions x where x.provider_id = p_provider and x.lane in ('aer_item', 'aer_course', 'aer_source')
                          and x.status in ('ai_pending', 'awaiting_input', 'resuming')),
    'admitted_courses', (select count(distinct q.course_id) from catalogue.course_entry_requirements q join catalogue.courses c on c.id = q.course_id
                          where c.provider_id = p_provider and q.status = 'active'),
    'admitted_matrix_rows', (select count(*) from catalogue.provider_entry_matrix m where m.provider_id = p_provider and m.status = 'active'),
    'by_route', (select jsonb_object_agg(z.route, z.n) from (select coalesce(s.route, 'unchecked') route, count(*) n from s group by 1) z))
$function$;
revoke all on function security.layer4_aer_university_summary_v1(uuid) from public, anon, authenticated;

create or replace function public.admin_layer4_aer_queue(p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 directions 10:00 §3 and 12:16 §5, §8: the reviewer-ready AER queue and one university's summary (Pipeline Operator and above; read
-- only). Decisions are made in Layer 4 › Inbox, one item at a time.
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 4 then raise exception 'Pipeline Operator or above required' using errcode = '42501'; end if;
  if coalesce(p_args, '{}'::jsonb) ? 'summary_provider_id' then return security.layer4_aer_university_summary_v1((p_args->>'summary_provider_id')::uuid); end if;
  return security.layer4_aer_queue_v1(coalesce(p_args, '{}'::jsonb));
end $function$;
revoke all on function public.admin_layer4_aer_queue(jsonb) from public, anon;
grant execute on function public.admin_layer4_aer_queue(jsonb) to authenticated;

create or replace function security.aer_progress_counts_v1(p_since timestamptz, p_provider uuid default null) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- CF-247 direction 12:16 §10: AER decisions since a time, counted separately: submitted (Inbox decide calls on AER items), saved (Layer 4
-- decisions recorded), admitted (rows made active by those decisions) and published (courses among them the website's course payload carries,
-- i.e. in the search projection with active rows). Read only.
  with dec as (select d.* from pipeline.layer4_decisions d join pipeline.layer4_review_items i on i.id = d.review_item_id
                left join catalogue.courses c on i.entity_type = 'course' and c.id = i.entity_id
               where d.created_at >= p_since and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change')
                 and (p_provider is null or coalesce(c.provider_id, case when i.entity_type = 'provider' then i.entity_id end) = p_provider))
  select jsonb_build_object('since', p_since,
    'submitted', (select count(*) from pipeline.admin_control_events e where e.area = 'layer4' and e.action = 'inbox_decide' and e.created_at >= p_since
                   and e.target like 'aer_review:%' and (p_provider is null or e.detail->>'provider_id' = p_provider::text)),
    'saved', (select count(*) from dec), 'saved_by_action', (select jsonb_object_agg(z.action, z.n) from (select dec.action, count(*) n from dec group by 1) z),
    'admitted_rows', (select count(*) from catalogue.course_entry_requirements x where x.status = 'active' and x.provenance->>'review_item_id' in (select dec.review_item_id::text from dec))
                     + (select count(*) from catalogue.provider_entry_matrix m join pipeline.entry_matrix_runs r on r.id = m.run_id where m.status = 'active' and r.review_item_id in (select dec.review_item_id from dec)),
    'admitted_courses', (select count(distinct x.course_id) from catalogue.course_entry_requirements x where x.status = 'active' and x.provenance->>'review_item_id' in (select dec.review_item_id::text from dec)),
    'published_courses', (select count(distinct x.course_id) from catalogue.course_entry_requirements x join search.course_documents d on d.course_id = x.course_id
                           where x.status = 'active' and x.provenance->>'review_item_id' in (select dec.review_item_id::text from dec)))
$function$;
revoke all on function security.aer_progress_counts_v1(timestamptz, uuid) from public, anon, authenticated;

create or replace function security.layer4_aer_owner_claim_v1(p_provider uuid, p_owner text, p_basis text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- a claim of one university's AER review (course reads and matrix runs) in the ownership register; refused while another owner holds it.
-- The Integration Controller mirrors it in admin docs/platform/nz-enrichment-brief/2026-11-03-layer4-review-ownership.md (single source).
declare v_other text; v_n int := 0; f text;
begin
  if p_owner not in ('claude', 'chatgpt', 'engineering') then raise exception 'owner must be claude, chatgpt or engineering' using errcode = '22023'; end if;
  if length(btrim(coalesce(p_basis, ''))) < 5 then raise exception 'give the basis of the claim'; end if;
  select string_agg(distinct o.owner, ', ') into v_other from pipeline.layer4_review_owners o
   where o.provider_id = p_provider and o.closed_at is null and o.owner <> p_owner and o.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change');
  if v_other is not null then return jsonb_build_object('claimed', false, 'reason', 'held by ' || v_other); end if;
  foreach f in array array['course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change'] loop
    insert into pipeline.layer4_review_owners(provider_id, field_code, owner, scope, basis, since, note)
    select p_provider, f, p_owner, 'AER review queue', btrim(p_basis), now(), 'direction 4 Nov 2026 10:00 §3'
     where not exists (select 1 from pipeline.layer4_review_owners o where o.provider_id = p_provider and o.field_code = f and o.owner = p_owner and o.closed_at is null);
    get diagnostics v_n = row_count;
  end loop;
  return jsonb_build_object('claimed', true, 'owner', p_owner, 'provider_id', p_provider);
end $function$;
revoke all on function security.layer4_aer_owner_claim_v1(uuid, text, text) from public, anon, authenticated;

-- 4 technical routing: one deduplicated intervention per held course read no automatic remedy can fix (lane aer_item's generator) ----------
create or replace function security.har_aer_item_generate_v1(p_limit int) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- shared page -> aer_course_identity (confirm the course the page belongs to); dropped minimums with no stored copy of the same page, or whose
-- corrected read was refused on the same stored copy, or out of tries -> aer_read_rows_missing (enter the dropped rows with their quotations).
-- From stored gate classes (job layer4-readiness), never a gate per row. Fair by university; deduplicated by the contract (an unchanged failure
-- only counts a repeat). Row-limit, source-is-matrix and matrix holds are authority or provider-level cases and are not raised here.
declare r record; v_res jsonb; v_n int := 0; v_rep int := 0; v_skip int := 0; v_per int := security.pipeline_num_v1('har.generate_per_provider_max', 2)::int;
        v_tries int := security.pipeline_num_v1('aer.schedule_held_max_tries', 2)::int;
begin
  for r in
    with h as (
      select i.id, i.entity_id, i.evidence_id, i.created_at, c.provider_id, coalesce(c.display_title, c.canonical_title) title, y.gate,
             security.aer_route_v1(i.field_code, y.gate) rt, pg.evidence_id page_ev, (pg.evidence_id is not null and pg.url = i.proposed_value->>'url') stored,
             (select count(*) from pipeline.aer_read_supersessions s where s.old_item_id = i.id) tries,
             exists (select 1 from pipeline.aer_read_supersessions s left join pipeline.field_enrich_items fe on fe.id = s.enrich_item_id
                      where s.old_item_id = i.id and s.state = 'refused' and (fe.evidence_id is null or fe.evidence_id = pg.evidence_id)) refused_same,
             (select s.outcome from pipeline.aer_read_supersessions s where s.old_item_id = i.id and s.state = 'refused' order by s.requested_at desc limit 1) refusal
        from pipeline.layer4_review_items i join pipeline.layer4_item_readiness y on y.item_id = i.id
        join catalogue.courses c on c.id = i.entity_id left join pipeline.coverage_course_pages pg on pg.course_id = i.entity_id
       where i.status = 'pending' and i.field_code = 'course_entry_first_read' and y.gate is not null),
    cand as (
      select h.*, case when h.rt->>'route' = 'identity' then 'aer_course_identity' else 'aer_read_rows_missing' end cls
        from h where h.rt->>'route' = 'identity'
          or (h.rt->>'route' in ('missing_scale', 'quote_association', 'low_confidence') and (not coalesce(h.stored, false) or h.refused_same or h.tries >= v_tries)
              -- direction 12:16 §3-§4: a read refused for the row limit kept every printed requirement; rows from a person would resume the same
              -- refused read, so it waits for the row boundary (authority) instead
              and coalesce(h.refusal, '') not ilike '%row limit%' and coalesce(h.refusal, '') not ilike '%proof does not admit%')),
    ranked as (select c.*, row_number() over (partition by c.provider_id order by c.created_at, c.id) pn from cand c
                where not exists (select 1 from pipeline.layer4_interventions x where x.entity = c.id::text and x.missing_fact = c.cls
                                    and x.status in ('ai_pending', 'awaiting_input', 'resuming') and x.fingerprint = md5(c.cls || '|' || md5(coalesce(c.gate::text, '') || '|' || coalesce(c.page_ev::text, '')))))
    select * from ranked where pn <= v_per order by pn, created_at, id limit greatest(coalesce(p_limit, 0), 0)
  loop
    v_res := security.layer4_intervention_raise_v1(jsonb_build_object('class', r.cls, 'entity', r.id::text, 'provider_id', r.provider_id, 'course_id', r.entity_id,
      'field', 'entry_requirements', 'attempts', 99,
      'subject', r.title || ': ' || case r.cls when 'aer_course_identity' then 'confirm the course this page belongs to' else 'dropped requirements to enter' end,
      'signature', md5(coalesce(r.gate::text, '') || '|' || coalesce(r.page_ev::text, '')),
      'issue', jsonb_build_object('summary', 'The read is held: ' || coalesce(r.gate->'reasons'->>0, r.rt->>'route'),
                                  'attempted', jsonb_build_array('AI course read', 'completeness gate (E13)') || case when r.tries > 0 then jsonb_build_array(r.tries || ' corrected read(s) from the stored copy') else '[]'::jsonb end,
                                  'why_stopped', case when r.cls = 'aer_course_identity' then 'the stored page is also another programme''s page'
                                                      when not coalesce(r.stored, false) then 'no stored copy of the same page to read again'
                                                      when r.refused_same then 'the corrected read was refused on the same stored copy (the reader gives the same result on unchanged evidence)'
                                                      else 'out of corrected-read tries' end,
                                  'impact', 'the course''s accurate rows cannot be admitted while the read is incomplete'),
      'evidence', jsonb_build_object('stored_copies', case when r.evidence_id is not null then jsonb_build_array(r.evidence_id) else '[]'::jsonb end,
                                     'quotes', coalesce((select jsonb_agg(d->'quote') from jsonb_array_elements(coalesce(r.gate->'drops_uncovered', '[]'::jsonb)) d where nullif(d->>'quote', '') is not null), '[]'::jsonb),
                                     'conflicts', coalesce(r.gate->'reasons', '[]'::jsonb), 'attempts', jsonb_build_array(jsonb_build_object('route', r.rt->>'route', 'tries', r.tries))),
      'resume_target', jsonb_build_object('operation', case when r.cls = 'aer_course_identity' then 'AER technical check of the held item' else 'corrected read of the course by the existing reader (D-R2)' end,
                                          'work_item', jsonb_build_object('lane', 'aer_technical', 'entity', r.id::text, 'kind', 'l4_item')),
      'review_item', r.id::text));
    if coalesce((v_res->>'raised')::boolean, false) then v_n := v_n + 1;
      update pipeline.layer4_interventions set resume_target = resume_target || jsonb_build_object('review_item', r.id::text) where id = (v_res->>'id')::bigint;
    elsif coalesce((v_res->>'repeat')::boolean, false) then v_rep := v_rep + 1; else v_skip := v_skip + 1; end if;
  end loop;
  return jsonb_build_object('raised_or_changed', v_n, 'repeats', v_rep, 'not_raised', v_skip);
end $function$;
revoke all on function security.har_aer_item_generate_v1(integer) from public, anon, authenticated;

update pipeline.layer4_intervention_handlers set generate_fn = 'security.har_aer_item_generate_v1(integer)', generate_switch = 'har.generate_aer_item_on'
 where lane = 'aer_item' and generate_fn is null;

-- 5 E13 recovery pilot: listed universities, a pilot total, never a read refused on the same stored copy ----------------------------------
select pg_temp.edit_once('security.aer_e13_recover_v1(boolean)', '90f80d59db94e29aab3fc520d1c99be6', '1bd8be8be44d5cd6e25a41a337b43f61', array[
  [$e$        v_asked jsonb := '[]'::jsonb; v_skip jsonb := '[]'::jsonb; v_cand int := 0;$e$,
   $e$        v_asked jsonb := '[]'::jsonb; v_skip jsonb := '[]'::jsonb; v_cand int := 0;
        -- 4 Nov 2026 (direction 10:00 §4): a bounded, reversible pilot: listed universities only, a total over the pilot, and never an item whose
        -- corrected read was refused on the same stored copy (the reader is deterministic on unchanged evidence)
        v_prov text[] := security.pipeline_list_v1('aer.e13_recover_providers', '[]'::jsonb); v_total int := security.pipeline_num_v1('aer.e13_recover_total_max', 40)::int; v_all int;$e$],
  [$e$  v_room := greatest(0, least(v_batch, v_day - v_used));$e$,
   $e$  select count(*) into v_all from pipeline.aer_read_supersessions s where s.reason like v_tag || '%';
  v_room := greatest(0, least(v_batch, v_day - v_used, v_total - v_all));$e$],
  [$e$                when v_room = 0 then 'the daily budget of E13 recovery is used (aer.e13_recover_daily_max)'$e$,
   $e$                when cardinality(v_prov) = 0 then 'no university is in the pilot (aer.e13_recover_providers)'
                when v_room = 0 and v_all >= v_total then 'the pilot total is used (aer.e13_recover_total_max)'
                when v_room = 0 then 'the daily budget of E13 recovery is used (aer.e13_recover_daily_max)'$e$],
  [$e$         and pg.evidence_id is not null and pg.url = i.proposed_value->>'url'$e$,
   $e$         and pg.evidence_id is not null and pg.url = i.proposed_value->>'url'
         and co.provider_id::text = any (v_prov)
         and not exists (select 1 from pipeline.aer_read_supersessions s left join pipeline.field_enrich_items fe on fe.id = s.enrich_item_id
                          where s.old_item_id = i.id and s.state = 'refused' and (fe.evidence_id is null or fe.evidence_id = pg.evidence_id))$e$],
  [$e$  return jsonb_build_object('on', v_on, 'preview', p_preview, 'refusal', null, 'used_24h', v_used, 'room', v_room, 'candidates', v_cand, 'asked', v_n,$e$,
   $e$  return jsonb_build_object('on', v_on, 'preview', p_preview, 'refusal', null, 'used_24h', v_used, 'pilot_used', v_all, 'room', v_room, 'candidates', v_cand, 'asked', v_n,$e$]],
  array[1, 1, 1, 1, 1]);

create or replace function security.aer_e13_pilot_report_v1() returns jsonb
language sql stable security definer set search_path to '' as $function$
-- the E13 recovery pilot's yield: corrected reads it asked, those that replaced the held read (superseded), refused (by reason), waiting, and
-- what became of the replacements (decided and admitted, or still waiting)
  with s as (select s.* from pipeline.aer_read_supersessions s where s.reason like 'AER technical recovery (E13)%')
  select jsonb_build_object('asked', (select count(*) from s), 'replaced', (select count(*) from s where s.state = 'superseded'),
    'refused', (select count(*) from s where s.state = 'refused'), 'waiting', (select count(*) from s where s.state = 'requested'),
    'yield_pct', (select round(100.0 * count(*) filter (where s.state = 'superseded') / nullif(count(*) filter (where s.state <> 'requested'), 0), 1) from s),
    'refused_why', (select jsonb_object_agg(k, n) from (select left(coalesce(s.outcome, 'unknown'), 80) k, count(*) n from s where s.state = 'refused' group by 1) z),
    'replacements_approved', (select count(*) from s join pipeline.layer4_review_items i on i.id = s.new_item_id where i.status in ('approved', 'edited_approved')),
    'replacements_waiting', (select count(*) from s join pipeline.layer4_review_items i on i.id = s.new_item_id where i.status = 'pending'),
    'by_university', (select jsonb_object_agg(z.pid, z.j) from (select c.provider_id::text pid, jsonb_build_object('asked', count(*), 'replaced', count(*) filter (where s.state = 'superseded')) j
                        from s join catalogue.courses c on c.id = s.course_id group by 1) z))
$function$;
revoke all on function security.aer_e13_pilot_report_v1() from public, anon, authenticated;

-- 6 what wc.aer_fair_on would do, from stored readiness (read only) -------------------------------------------------------------------------
create or replace function security.aer_fair_projection_v1() returns jsonb
language sql stable security definer set search_path to '' as $function$
-- the room and each university's share if wc.aer_fair_on were 1: distinct reviewer-ready decisions (route review, review_except, matrix_except,
-- from stored gate classes) and reads in progress against aer.schedule_layer4_max; each university at most wc.aer_provider_share_pct of it;
-- the last wc.aer_new_provider_reserve_pct kept for universities with nothing waiting. Items never gated are counted apart (they would count as
-- ready under today's readiness until gated).
  with lim as (select security.pipeline_num_v1('aer.schedule_layer4_max', 600) l,
                      ceil(security.pipeline_num_v1('aer.schedule_layer4_max', 600) * security.pipeline_num_v1('wc.aer_provider_share_pct', 10) / 100.0) share,
                      ceil(security.pipeline_num_v1('aer.schedule_layer4_max', 600) * security.pipeline_num_v1('wc.aer_new_provider_reserve_pct', 10) / 100.0) reserve),
       q as (select distinct on (i.entity_id, i.field_code) i.entity_id, i.field_code, coalesce(c.provider_id, case when i.entity_type = 'provider' then i.entity_id end) pid,
                    security.aer_route_v1(i.field_code, y.gate)->>'route' route
               from pipeline.layer4_review_items i left join pipeline.layer4_item_readiness y on y.item_id = i.id
               left join catalogue.courses c on i.entity_type = 'course' and c.id = i.entity_id
              where i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change')
              order by i.entity_id, i.field_code, i.created_at),
       prog as (select f.provider_id pid, count(distinct coalesce(f.course_id, f.provider_id)) n from pipeline.field_enrich_items f
                 where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased') group by 1),
       p as (select q.pid, count(*) filter (where q.route in ('review', 'review_except', 'matrix_except')) ready, count(*) filter (where q.route = 'awaiting_gate') unchecked,
                    count(*) filter (where q.route not in ('review', 'review_except', 'matrix_except', 'awaiting_gate')) held from q group by 1)
  select jsonb_build_object('limit', lim.l, 'share', lim.share, 'reserve', lim.reserve,
    'ready', (select sum(ready) from p), 'unchecked', (select sum(unchecked) from p), 'held', (select sum(held) from p), 'in_progress', coalesce((select sum(n) from prog), 0),
    'room_now', greatest(lim.l - coalesce((select sum(ready + unchecked) from p), 0) - coalesce((select sum(n) from prog), 0), 0),
    'room_when_gated', greatest(lim.l - coalesce((select sum(ready) from p), 0) - coalesce((select sum(n) from prog), 0), 0),
    'universities', coalesce((select jsonb_agg(jsonb_build_object('provider_id', p.pid, 'name', coalesce(pv.display_name, pv.canonical_name), 'ready', p.ready, 'unchecked', p.unchecked,
                     'held', p.held, 'in_progress', coalesce(prog.n, 0), 'new_reads_allowed', greatest(lim.share - p.ready - coalesce(prog.n, 0), 0),
                     'at_share', p.ready + coalesce(prog.n, 0) >= lim.share) order by p.ready + p.unchecked + p.held desc)
               from p left join prog on prog.pid = p.pid left join catalogue.providers pv on pv.id = p.pid), '[]'::jsonb))
  from lim
$function$;
revoke all on function security.aer_fair_projection_v1() from public, anon, authenticated;

-- 7 component register ----------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.aer_route_v1', 'Platform', 'CF-247 AER: the class and route of a waiting AER item from its gate result', 'active', '{}', '20261104530000'),
 ('function', 'security.aer_review_packet_v1', 'Platform', 'CF-247 AER: one item''s review packet (direction 10:00 §3)', 'active', '{}', '20261104530000'),
 ('function', 'security.layer4_aer_review_detail_v1', 'Layer 4', 'CF-247 AER card detail: the review packet, then the recovery detail', 'active', '{security.layer4_aer_recovery_detail_v1 (as hook detail)}', '20261104530000'),
 ('function', 'security.layer4_aer_queue_v1', 'Layer 4', 'CF-247 AER reviewer-ready queue by university', 'active', '{}', '20261104530000'),
 ('function', 'public.admin_layer4_aer_queue', 'Layer 4', 'CF-247 AER reviewer-ready queue (Pipeline Operator and above, read only)', 'active', '{}', '20261104530000'),
 ('function', 'security.layer4_aer_owner_claim_v1', 'Layer 4', 'CF-247 a claim of one university''s AER review in the ownership register', 'active', '{}', '20261104530000'),
 ('function', 'security.har_aer_item_generate_v1', 'Platform', 'CF-247 interventions for held AER course reads no automatic remedy can fix (lane aer_item)', 'active', '{}', '20261104530000'),
 ('function', 'security.aer_e13_pilot_report_v1', 'Platform', 'CF-247 the E13 recovery pilot''s replacement yield', 'active', '{}', '20261104530000'),
 ('function', 'security.aer_fair_projection_v1', 'Platform', 'CF-247 what wc.aer_fair_on would do now, by university', 'active', '{}', '20261104530000')
on conflict do nothing;

-- 8 post-check ------------------------------------------------------------------------------------------------------------------------------
do $p$
begin
  if (select detail_fn from pipeline.layer4_inbox_kind_hooks where kind = 'aer_review' and mode = 'extend') is distinct from 'security.layer4_aer_review_detail_v1(text)' then
    raise exception 'post-check: the aer_review extend hook does not read the review packet';
  end if;
  if (select generate_fn::text from pipeline.layer4_intervention_handlers where lane = 'aer_item') is distinct from 'security.har_aer_item_generate_v1(integer)' then
    raise exception 'post-check: lane aer_item has no generator';
  end if;
  if not exists (select 1 from pipeline.admin_control_events e where e.target like '%aer.e13_recover_on%')
     and (select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'aer.e13_recover_on') is distinct from 0 then
    raise exception 'post-check: aer.e13_recover_on must stay off';
  end if;
end $p$;
