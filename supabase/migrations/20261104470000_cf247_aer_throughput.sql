-- CF-247 AER throughput (Platform Admin mandate 4 Nov 2026 08:16 §8 "Restore AER throughput"; §4 progress contract, §5 recovery loop, §6 switches).
-- Investigation: admin docs/platform/2026-11-04-aer-throughput-investigation.md (live, read only, 4 Nov 2026 08:19-08:33 AEDT).
-- Why (measured live):
--   * 605 AER items wait in Layer 4 (564 course reads, 41 matrix runs). The completeness gate (E13, D-R2/D-R3) holds 395 of the 564 course reads
--     (162 cut at the row limit, 45 on a page shared with another programme, 163 dropping printed minimums no row covers, 25 row-level only);
--     169 are complete and wait for a person. No AER item has been decided since 1 Nov 19:47.
--   * Readiness starves the gate: security.layer4_readiness_tick_v1 gates at most layer4.gate_batch (20) items a run, in the order the items
--     are re-classified, and re-classifies an item only every layer4.readiness_recheck_minutes (120). The same oldest items take the gate each
--     cycle; 376 of the 395 held course reads have never been gated (gate_checked_at null) and are classified judgement_ready. So:
--     security.aer_technical_recovery_v1 (which acts on technical_blocked only) has seen 19 of them; the review room of wc.aer_fair_on would
--     count them as decisions (it would free nothing); Human-assisted recovery (v2.15.463) cannot find shared-page reads among parked work.
--   * The scheduled correction (D-R2 through security.aer_schedule_held_v1) spends the same daily cap as new reads (aer.schedule_daily_max 200):
--     93 of the 200 reads of 3-4 Nov were corrections; of the 103 closed corrections 10 replaced the held read and 90 were refused (63 still
--     dropping printed minimums, 15 cut at the row limit). The cap was reached at 03:13 and the raw count 605 >= 600 stops new reads.
-- What:
--   1. Readiness gates never-gated entry reads first (security.layer4_readiness_tick_v1, md5-guarded edit): an entry item with no gate result
--      is classified again every run until it is gated, and takes the gate before items already gated. layer4.gate_batch is unchanged (the
--      Integration Controller may raise it on Settings > Pipeline settings). Records only: no Layer 4 item, decision, read or spend changes.
--   2. Technical recovery records the gate class (security.aer_e13_class_v1: row_limit, shared_page, drops_uncovered, row_level) in the
--      technical_hold evidence, so Human-assisted recovery's generator finds shared-page reads (its pattern matches shared_page) and the
--      report says which holds a re-read can fix (security.aer_technical_recovery_v1, md5-guarded edit). Records only.
--   3. E13 recovery from stored evidence (security.aer_e13_recover_v1, called by security.aer_technical_recovery_v1 each run of
--      aer-scheduled-read, isolated): readiness-aware (technical_blocked by the completeness gate, the gate re-checked before acting), only
--      reads a re-read can fix (dropped printed minimums; never the row limit or a shared page), only where the stored copy of the same page
--      exists (security.course_entry_read_enqueue_v1 reads with the scraper off: no Firecrawl), through the existing corrected-read path
--      (security.course_entry_correction_v1, D-R2: replaces the held read only when complete), at most aer.schedule_held_max_tries tries an
--      item spaced aer.schedule_held_retry_days, fair by university (aer.e13_recover_per_provider a run, fewest tries first), at most
--      batch.aer_e13_recover a run and aer.e13_recover_daily_max a day (its own budget, beside aer.schedule_daily_max), only while AI reading
--      (enrich_fields) is allowed, the run-as owner holds the Platform Admin rank, and the OpenRouter balance stays above its floor.
--      While aer.e13_recover_on is 1, the scheduled tick's held step yields to it (security.aer_schedule_held_v1, md5-guarded edit), so the
--      daily cap of new reads is no longer spent on corrections. security.aer_e13_recover_v1(true) previews a run without writing.
--   Nothing approves, rejects or decides an entry requirement; the 600 limit, E13 and D-R3 are unchanged; nothing is dropped or deleted.
-- Activation:
--   ON (records only): 1 and 2.
--   OFF (AI spend outside the existing daily cap; needs the Platform Admin's decision): aer.e13_recover_on. Expected: about 1 in 10 corrected
--     reads replaced its held read (10 of 103); at US$0.00609 a read, the default 40 a day is about US$0.24 a day.
-- Settings (G2; Settings > Pipeline settings, section Entry requirements): aer.e13_recover_on, batch.aer_e13_recover, aer.e13_recover_daily_max,
--   aer.e13_recover_per_provider. Reused: aer.schedule_held_max_tries, aer.schedule_held_retry_days.
-- Before (live, 4 Nov 2026 08:19 AEDT) -> after:
--   security.layer4_readiness_tick_v1() 5ed0f7d1ba89c9248403fa4bce76d6fe -> 06e5f4394b0c2831404fc7a766d669c4
--   security.aer_technical_recovery_v1() 3b8ea81abeae4b7d45f43e8cdb27ed26 -> 370baa57bfb81fe58df767ad852ca9dd
--   security.aer_schedule_held_v1(integer) 0ea5886c2956255ea2d3f102c64b0166 -> 2a0d51faada02e5e36dafb88749b4707
--   Called, not edited (checked): security.course_entry_correction_v1(uuid,uuid,text) 1e2947b30a02a38327e2b67e312339af,
--   security.course_entry_read_enqueue_v1(uuid,uuid,text) df0f2a2826e61b92b168847f1557435b, security.work_item_report_v1(text,text,text,text,jsonb)
--   6a15318c0ecd6644b32f1883463c542e.
-- Replaces: nothing (the scheduled tick's held step yields to E13 recovery only while aer.e13_recover_on is 1)
-- Retires: nothing
-- Rollback: re-apply the three before definitions (tests/fixtures/aer-throughput/live/); the two new functions and four settings stay unused.

-- 0 the definitions this change calls or edits, as read live ---------------------------------------------------------------------------------
do $g$
declare r record;
begin
  for r in select * from (values ('security.course_entry_correction_v1(uuid,uuid,text)', '1e2947b30a02a38327e2b67e312339af'),
                                 ('security.course_entry_read_enqueue_v1(uuid,uuid,text)', 'df0f2a2826e61b92b168847f1557435b'),
                                 ('security.work_item_report_v1(text,text,text,text,jsonb)', '6a15318c0ecd6644b32f1883463c542e')) v(sig, m) loop
    if to_regprocedure(r.sig) is null then raise exception 'live % is missing', r.sig; end if;
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then
      raise exception 'live % differs from the definition this change was written against (md5 %)', r.sig, md5(pg_get_functiondef(r.sig::regprocedure)); end if;
  end loop;
  for r in select * from (values ('security.course_entry_gate_v1(uuid,uuid[])'), ('security.ai_use_refusal_v1(text)'), ('security.course_entry_cost_v1()')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'live % is missing', r.sig; end if;
  end loop;
end $g$;

-- an edit applied once, only from the definition it was written against (the 20261103050000 helper)
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

-- 1 settings (G2; Settings > Pipeline settings, section Entry requirements) ------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.e13_recover_on', 'Entry requirements: re-read held reads from stored evidence (E13 recovery)',
  'On (1): each run of aer-scheduled-read asks the existing corrected read (D-R2) of held course reads a re-read can fix (dropped printed minimums), from the stored copy of the same page, within its own daily budget; the scheduled held step then yields to it. Off (0): held reads are re-read only by the scheduled held step within the daily cap, or by a reviewer.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1460, 'Entry requirements', 'security.aer_e13_recover_v1 (job aer-scheduled-read); security.aer_schedule_held_v1',
  'Mandate 4 Nov 2026 08:16 §8: ships off (AI spend outside the existing daily cap needs a decision)'),
 ('pipeline', 'batch.aer_e13_recover', 'Entry requirements: held reads re-read a run (E13 recovery)',
  'At most this many held course reads are given a corrected read from stored evidence in one run of aer-scheduled-read.',
  'number', to_jsonb(10), 1, 50, 'reads a run', 1461, 'Entry requirements', 'security.aer_e13_recover_v1', 'Mandate 4 Nov 2026 08:16 §8 "technical recovery"'),
 ('pipeline', 'aer.e13_recover_daily_max', 'Entry requirements: held reads re-read a day (E13 recovery)',
  'At most this many corrected reads from stored evidence are asked by E13 recovery in 24 hours. Counted apart from the daily cap of new course reads (aer.schedule_daily_max).',
  'number', to_jsonb(40), 0, 200, 'reads a day', 1462, 'Entry requirements', 'security.aer_e13_recover_v1', 'Mandate 4 Nov 2026 08:16 §8: the cap of new reads is not spent on unreviewable work'),
 ('pipeline', 'aer.e13_recover_per_provider', 'Entry requirements: held reads re-read per university a run (E13 recovery)',
  'At most this many held reads of one university are re-read in one run, fewest tries first, so one university cannot take the run.',
  'number', to_jsonb(2), 1, 20, 'reads per university', 1463, 'Entry requirements', 'security.aer_e13_recover_v1', 'Mandate 4 Nov 2026 08:16 §8 "provider fairness"')
on conflict (toolset_key, key) do nothing;

-- 2 functions ---------------------------------------------------------------------------------------------------------------------------------
create or replace function security.aer_e13_class_v1(p_gate jsonb) returns text
language sql immutable set search_path to '' as $function$
-- the class of a course entry gate result (security.course_entry_gate_v1): what could release the hold. complete; row_limit (rows cut at the row
-- limit: a re-read cuts them again); shared_page (the page is another programme's too: a person confirms the course); drops_uncovered (printed
-- minimums dropped: a re-read can fix); row_level (rows a person leaves out with Approve except); null without a gate result
  select case when p_gate is null then null
              when coalesce((p_gate->>'complete')::boolean, false) then 'complete'
              when coalesce((p_gate->>'rows_cut')::int, 0) > 0 then 'row_limit'
              when jsonb_array_length(coalesce(p_gate->'shared_page', '[]'::jsonb)) > 0 then 'shared_page'
              when jsonb_array_length(coalesce(p_gate->'drops_uncovered', '[]'::jsonb)) > 0 then 'drops_uncovered'
              else 'row_level' end
$function$;
revoke all on function security.aer_e13_class_v1(jsonb) from public, anon, authenticated;

create or replace function security.aer_e13_recover_v1(p_preview boolean default false) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 AER throughput (mandate 4 Nov 2026 08:16 §8): held course reads a re-read can fix get the existing corrected read (D-R2) from the stored
-- copy of the same page. Readiness-aware (technical_blocked by the completeness gate; the gate is re-checked before acting), fair by university,
-- bounded a run and a day by settings, and only while aer.e13_recover_on is 1 (p_preview says what a run would ask, without writing).
-- The corrected read replaces the held read only when it is complete (security.enrich_entry_record_v1); nothing is approved here.
declare v_on boolean := security.pipeline_num_v1('aer.e13_recover_on', 0) >= 1;
        v_batch int := security.pipeline_num_v1('batch.aer_e13_recover', 10)::int;
        v_day int := security.pipeline_num_v1('aer.e13_recover_daily_max', 40)::int;
        v_per int := security.pipeline_num_v1('aer.e13_recover_per_provider', 2)::int;
        v_tries int := security.pipeline_num_v1('aer.schedule_held_max_tries', 2)::int;
        v_retry interval := make_interval(days => security.pipeline_num_v1('aer.schedule_held_retry_days', 14)::int);
        v_tag text := 'AER technical recovery (E13)';
        v_owner uuid; v_rank int; v_ai text; v_bal numeric; v_floor numeric; v_cost numeric := security.course_entry_cost_v1();
        v_used int; v_room int; v_why text; r record; g jsonb; v_res jsonb; v_n int := 0;
        v_asked jsonb := '[]'::jsonb; v_skip jsonb := '[]'::jsonb; v_cand int := 0;
begin
  select c.owner into v_owner from pipeline.field_gap_queue_control c where c.id = 1;
  select ro.rank into v_rank from security.user_roles ur join security.roles ro on ro.code = ur.role_code
   where ur.user_id = v_owner and (ur.expires_at is null or ur.expires_at > now()) and ro.status = 'active' order by ro.rank desc limit 1;
  select count(*) into v_used from pipeline.aer_read_supersessions s
   where s.requested_at > now() - interval '1 day' and s.reason like v_tag || '%';  -- fixed: the daily budget is counted over the last 24 hours
  v_room := greatest(0, least(v_batch, v_day - v_used));
  v_ai := security.ai_use_refusal_v1('enrich_fields');
  select o.remaining_usd into v_bal from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;
  v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
  v_why := case when not v_on and not p_preview then 'aer.e13_recover_on is 0'
                when v_owner is null then 'no owner to run as (Coverage > Attributes, Fill the gaps)'
                when coalesce(v_rank, 0) < 6 then 'the owner it runs as does not hold the Platform Admin role'  -- fixed: the rank Read next batch requires
                when v_ai is not null then 'AI reading is stopped (AI limits): ' || v_ai
                when v_room = 0 then 'the daily budget of E13 recovery is used (aer.e13_recover_daily_max)'
                when v_bal is not null and v_bal - v_room * v_cost < v_floor then 'the estimate would take the OpenRouter balance below its floor (Toolsets & limits)' end;
  if v_why is not null and not (p_preview and v_why = 'aer.e13_recover_on is 0') then
    return jsonb_build_object('on', v_on, 'preview', p_preview, 'refusal', v_why, 'used_24h', v_used, 'room', v_room, 'asked', 0);
  end if;
  for r in
    with c as (
      select i.id, i.entity_id, i.created_at, co.provider_id,
             (select count(*) from pipeline.aer_read_supersessions s where s.old_item_id = i.id) tries
        from pipeline.layer4_review_items i
        join pipeline.layer4_item_readiness x on x.item_id = i.id
        join catalogue.courses co on co.id = i.entity_id
        join pipeline.coverage_course_pages pg on pg.course_id = i.entity_id
       where i.status = 'pending' and i.field_code = 'course_entry_first_read'
         and x.readiness = 'technical_blocked' and 'completeness_gate' = any (x.reasons)
         and security.aer_e13_class_v1(x.gate) = 'drops_uncovered'
         and pg.evidence_id is not null and pg.url = i.proposed_value->>'url'
         and not exists (select 1 from pipeline.aer_read_supersessions s where s.old_item_id = i.id and (s.state = 'requested' or s.requested_at > now() - v_retry))
         and not exists (select 1 from pipeline.field_enrich_items f where f.course_id = i.entity_id and f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased'))),
    k as (select c.*, row_number() over (partition by c.provider_id order by c.tries, c.created_at, c.id) turn from c where c.tries < v_tries)
    select * from k where k.turn <= v_per order by k.turn, k.tries, k.created_at, k.id
  loop
    exit when v_n >= v_room;
    v_cand := v_cand + 1;
    -- the gate result may be older than the item's last change: checked again before anything is asked
    g := security.course_entry_gate_v1(r.id);
    if security.aer_e13_class_v1(g) is distinct from 'drops_uncovered' then
      v_skip := v_skip || jsonb_build_object('item_id', r.id, 'why', 'the gate now says ' || coalesce(security.aer_e13_class_v1(g), 'nothing'));
      continue;
    end if;
    if p_preview then
      v_asked := v_asked || jsonb_build_object('item_id', r.id, 'course_id', r.entity_id, 'provider_id', r.provider_id, 'tries', r.tries); v_n := v_n + 1;
      continue;
    end if;
    begin
      v_res := security.course_entry_correction_v1(r.id, v_owner,
                 v_tag || ': the held read dropped printed requirements that no row covers; read again from the stored copy of the same page (try ' || (r.tries + 1) || ')');
      v_asked := v_asked || jsonb_build_object('item_id', r.id, 'course_id', r.entity_id, 'provider_id', r.provider_id, 'tries', r.tries, 'job_id', v_res->>'job_id');
      v_n := v_n + 1;
    exception when others then
      v_skip := v_skip || jsonb_build_object('item_id', r.id, 'why', left(sqlerrm, 300));
    end;
  end loop;
  return jsonb_build_object('on', v_on, 'preview', p_preview, 'refusal', null, 'used_24h', v_used, 'room', v_room, 'candidates', v_cand, 'asked', v_n,
                            'estimate_usd', round(v_n * v_cost, 4), 'items', v_asked, 'skipped', v_skip);
end $function$;
revoke all on function security.aer_e13_recover_v1(boolean) from public, anon, authenticated;

-- 3 md5-guarded edits -------------------------------------------------------------------------------------------------------------------------
-- 3.1 readiness gates never-gated entry reads first
select pg_temp.edit_once('security.layer4_readiness_tick_v1()', '5ed0f7d1ba89c9248403fa4bce76d6fe', '06e5f4394b0c2831404fc7a766d669c4', array[
  [$e$--     with blockers, route and the kind's measured reviewer minutes; entry-requirement gates for at most layer4.gate_batch items. Items no
--     longer waiting are closed.$e$,
   $e$--     with blockers, route and the kind's measured reviewer minutes; entry-requirement gates for at most layer4.gate_batch items. Items no
--     longer waiting are closed. 4 Nov 2026 (AER throughput, mandate 08:16 §8): an entry item never gated is classified again every run until
--     it is gated, and takes the gate before items already gated, so a held read is not reported judgement_ready for want of a gate.$e$],
  [$e$                and (x.item_id is null or x.classified_at < now() - make_interval(mins => security.pipeline_num_v1('layer4.readiness_recheck_minutes', 120)::int))
              order by x.classified_at nulls first, i.created_at$e$,
   $e$                and (x.item_id is null or x.classified_at < now() - make_interval(mins => security.pipeline_num_v1('layer4.readiness_recheck_minutes', 120)::int)
                     or (x.gate_checked_at is null and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change')))
              order by (x.gate_checked_at is null and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change')) desc,
                       x.classified_at nulls first, i.created_at$e$]], array[1, 1]);

-- 3.2 technical recovery records the gate class and runs E13 recovery (isolated)
select pg_temp.edit_once('security.aer_technical_recovery_v1()', '3b8ea81abeae4b7d45f43e8cdb27ed26', '370baa57bfb81fe58df767ad852ca9dd', array[
  [$e$-- or leaves the queue is recovered. Records only: no Layer 4 item, decision or value is changed.
declare v_n int := security.pipeline_num_v1('wc.tick_batch', 500)::int; r record; v_t int := 0; v_d int := 0; v_ok int := 0;$e$,
   $e$-- or leaves the queue is recovered. Records only: no Layer 4 item, decision or value is changed.
-- 4 Nov 2026 (AER throughput, mandate 08:16 §8): the technical_hold evidence carries the gate class (security.aer_e13_class_v1), and each run
-- ends with E13 recovery from stored evidence (security.aer_e13_recover_v1; it asks nothing while aer.e13_recover_on is 0), isolated.
declare v_n int := security.pipeline_num_v1('wc.tick_batch', 500)::int; r record; v_t int := 0; v_d int := 0; v_ok int := 0; v_e13 jsonb;$e$],
  [$e$  for r in select i.id, i.entity_id, i.entity_type, i.field_code, x.reasons, x.route, x.blockers, c.provider_id$e$,
   $e$  for r in select i.id, i.entity_id, i.entity_type, i.field_code, x.reasons, x.route, x.blockers, c.provider_id, x.gate, x.gate_checked_at$e$],
  [$e$              'evidence', jsonb_build_object('route', r.route, 'blockers', r.blockers)));$e$,
   $e$              'evidence', jsonb_build_object('route', r.route, 'blockers', r.blockers, 'gate_class', security.aer_e13_class_v1(r.gate), 'gate_checked_at', r.gate_checked_at,
                                             'reread_can_fix', security.aer_e13_class_v1(r.gate) = 'drops_uncovered')));$e$],
  [$e$  return jsonb_build_object('technical_checked', v_t, 'duplicates_parked', v_d, 'recovered', v_ok);$e$,
   $e$  begin
    v_e13 := security.aer_e13_recover_v1(false);
  exception when others then v_e13 := jsonb_build_object('error', left(sqlerrm, 200));
  end;
  return jsonb_build_object('technical_checked', v_t, 'duplicates_parked', v_d, 'recovered', v_ok, 'e13_recover', v_e13);$e$]], array[1, 1, 1, 1]);

-- 3.3 the scheduled held step yields to E13 recovery while it is on (the daily cap of new reads is not spent on corrections)
select pg_temp.edit_once('security.aer_schedule_held_v1(integer)', '0ea5886c2956255ea2d3f102c64b0166', '2a0d51faada02e5e36dafb88749b4707', array[
  [$e$  if coalesce(p_limit, 0) <= 0 then return; end if;$e$,
   $e$  if coalesce(p_limit, 0) <= 0 then return; end if;
  -- 4 Nov 2026 (AER throughput, mandate 08:16 §8): while E13 recovery is on it owns corrected reads of held items, within its own budget
  if security.pipeline_num_v1('aer.e13_recover_on', 0) >= 1 then return; end if;$e$]], array[1]);

-- 4 component register ----------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.aer_e13_class_v1', 'Platform', 'CF-247 AER throughput: the class of a course entry gate result (what could release the hold)', 'active', '{}', '20261104470000'),
 ('function', 'security.aer_e13_recover_v1', 'Platform', 'CF-247 AER throughput: held course reads re-read from stored evidence (D-R2), fair and bounded; off by default', 'active', '{}', '20261104470000')
on conflict do nothing;

-- 5 post-check ------------------------------------------------------------------------------------------------------------------------------
do $p$
begin
  -- the switch that spends ships off; a value already set by the Platform Admin through Settings is kept (on conflict do nothing)
  if not exists (select 1 from pipeline.admin_control_events e where e.target like '%aer.e13_recover_on%')
     and (select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'aer.e13_recover_on') is distinct from 0 then
    raise exception 'post-check: aer.e13_recover_on must ship off';
  end if;
end $p$;
