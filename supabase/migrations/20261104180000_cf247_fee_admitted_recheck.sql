-- CF-247 IQ-00111 D12 (Platform Admin decision D12, overnight autonomous execution mandate 3 Nov 2026 21:59): send admitted AI fees that sit
-- on a course a person already decided ("Fee fails the check") to Layer 4, with their evidence and the earlier decisions attached, without
-- overwriting a decided item. A reusable "re-check this admitted fee" route on the existing fee check card.
-- Why (live, read-only, 3 Nov 2026 22:0x AEDT): 6 active AI fee reader rows were admitted on courses whose fee check hold a person had released
-- with "the page figure is not an annual fee" or "Keep the CRICOS total" (the reader did not look at holds until 20261104140000). One (Reach
-- 106655B, 2bc5fcb3) was withdrawn by the IQ-00111 containment paste; 5 remain active and visible to consumers: NTI 072350D 23,800, UTas
-- 093282D 18,167 and 114382M 27,338, Reach 105389A 11,500, AIH 107010J 15,000. The fee check card today: "Keep the CRICOS total" only releases
-- the hold (admin_layer4_inbox -> security.flag_release_v1), so an active AI fee would stay; and the course card links no stored copy (audit
-- 19:50: "fee cards say no stored copy is linked").
-- What:
--   1 security.fee_admitted_recheck_v1(fee, reason, actor): raises one new fee check item for an active AI fee (pipeline.enrichment_flags,
--     reason_code fee_crosscheck so it is the existing "Fee fails the check" card; field fee_ai_recheck so it never touches the decided flag of
--     field fee). Its evidence carries the fee, the stored copy, the quote, the CRICOS total, the exclusion and every earlier decision. Refused for
--     a manual value, a non-AI fee, an inactive fee, or a course already re-checked. Called by the governed paste (service or Platform Admin only).
--   2 security.fee_admitted_recheck_settle_tg (AFTER UPDATE on pipeline.enrichment_flags): when a person releases such an item ("Keep the CRICOS
--     total"), the AI fee it names is withdrawn (status inactive, note; the established fee status path) if it is still the same active value,
--     scholarship savings are recomputed and the search projection refreshed. "Open the course" (enter or confirm the fee by hand) supersedes the
--     AI fee through admin_course_edit as today. Setting fees.recheck_keep_withdraws_on ships ON: it only carries out a person's recorded decision,
--     limited to items this route raised; without it the card's "the page fee stays out" would be untrue.
--   3 security.layer4_inbox_items_v1: a course fee check card links its stored copy (the flag's own evidence, else the course page held) and
--     carries a re-check's evidence. Detail keys are added; nothing is renamed or removed. Not consumer API.
-- Edited live function (md5 read live 3 Nov 2026 22:0x AEDT; guarded both ways):
--   security.layer4_inbox_items_v1() a56bc3313e02ac0611deb5657da95ce0 -> c930125d7fda6efb4793b78eed0a10b5
-- Replaces: nothing (the "Keep the CRICOS total" release is unchanged for every other fee check item)
-- Retires: nothing
-- Nothing is dropped or deleted. No consumer API object changes (G3). No Firecrawl or AI spend. No item is decided by this change.

do $g$
begin
  if to_regclass('pipeline.ops_remedies') is null then
    raise exception 'workstream A''s operations contract (migration 20261104010000) must be applied before this change';
  end if;
  if to_regprocedure('security.fee_reader_hold_v1(uuid)') is null then
    raise exception 'migration 20261104140000 (fee reader units and holds) must be applied before this change';
  end if;
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

-- 1 setting (G2) ------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'fees.recheck_keep_withdraws_on', 'Fee re-check: "Keep the CRICOS total" withdraws the AI fee',
  'On (1): when a person keeps the CRICOS total on a fee check item raised to re-check an admitted AI fee, that AI fee is withdrawn (status inactive, with the decision in its note) and the CRICOS registered fee is used. Off (0): the item is released and the AI fee stays.',
  'number', to_jsonb(1), 0, 1, 'on/off', 356, 'Enrichment', 'security.fee_admitted_recheck_settle_tg',
  'IQ-00111 D12 (Platform Admin 3 Nov 2026 21:59): ships on; it carries out a person''s recorded decision only, for items raised by the re-check route')
on conflict (toolset_key, key) do nothing;

-- 2 raise one re-check item for an admitted AI fee -----------------------------------------------------------------------------------------------
create or replace function security.fee_admitted_recheck_v1(p_fee uuid, p_reason text, p_actor text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 IQ-00111 D12: one new "Fee fails the check" item for an active AI fee, with the fee, the stored copy, the quote, the CRICOS total, the
-- exclusion and every earlier decision attached. Never changes a decided item (a new flag of field fee_ai_recheck); never touches a manual value.
declare f catalogue.course_fees%rowtype; v_c catalogue.courses%rowtype; v_ev jsonb; v_id bigint; v_why text; v_prior jsonb;
begin
  if length(btrim(coalesce(p_reason, ''))) < 10 then raise exception 'give the reason for the re-check' using errcode = '22023'; end if;
  select * into f from catalogue.course_fees where id = p_fee;
  if f.id is null or f.fee_type <> 'provider_current_tuition' or f.status <> 'active' or coalesce(f.notes, '') not like '%AI fee reader (%' then
    return jsonb_build_object('fee_id', p_fee, 'raised', false, 'why', 'not an active AI fee reader value');
  end if;
  if exists (select 1 from pipeline.manual_locks m where m.entity = 'course' and m.entity_id = f.course_id) then
    return jsonb_build_object('fee_id', p_fee, 'raised', false, 'why', 'the course has a manual value; it is never re-checked automatically');
  end if;
  if exists (select 1 from pipeline.enrichment_flags x where x.entity = 'course' and x.entity_key = f.course_id::text and x.field = 'fee_ai_recheck') then
    return jsonb_build_object('fee_id', p_fee, 'raised', false, 'why', 'this course already has a re-check item (raised or decided)');
  end if;
  select * into v_c from catalogue.courses where id = f.course_id;
  select coalesce(jsonb_agg(jsonb_build_object('flag_id', x.id, 'state', x.state, 'flagged_at', x.flagged_at, 'released_at', x.released_at, 'released_by', x.released_by,
                                               'release_kind', x.release_kind, 'reason', x.reason, 'release_reason', x.release_reason) order by x.flagged_at), '[]'::jsonb)
    into v_prior from pipeline.enrichment_flags x
   where x.entity = 'course' and x.entity_key = f.course_id::text and x.reason_code = 'fee_crosscheck';
  v_ev := jsonb_build_object(
    'fee_id', f.id, 'amount', f.amount, 'currency', f.currency_code, 'fee_year', f.fee_year, 'basis', f.basis, 'admitted_at', f.created_at, 'notes', f.notes,
    'evidence_id', f.evidence_id,
    'source_url', (select e.source_url from pipeline.evidence_artifacts e where e.id = f.evidence_id),
    'captured_at', (select e.captured_at from pipeline.evidence_artifacts e where e.id = f.evidence_id),
    'quote', (select x.quote from pipeline.fee_reader_rows x where x.course_id = f.course_id and x.outcome = 'admitted' order by x.created_at desc limit 1),
    'cricos_total', (select r.amount from catalogue.course_fees r where r.course_id = f.course_id and r.fee_type = 'tuition' and r.basis = 'registered_total_course'
                       and r.status = 'active' order by r.created_at desc limit 1),
    'exclusion', (select jsonb_build_object('reason', e.reason, 'set_at', e.set_at) from pipeline.uni_adapter_exclusions e where e.course_id = f.course_id and e.field = 'fee' and e.active),
    'earlier_decisions', v_prior, 'raised_reason', p_reason, 'route', 'security.fee_admitted_recheck_v1');
  v_why := 'Re-check an admitted AI fee: ' || coalesce(f.currency_code, '') || ' ' || to_char(f.amount, 'FM999,999,990.00') || coalesce(' for ' || f.fee_year, '')
        || ' is active, but a person decided earlier: ' || coalesce((select left(e->>'release_reason', 160) from jsonb_array_elements(v_prior) e where e->>'state' = 'released' order by e->>'released_at' desc limit 1), 'no earlier decision')
        || '. Confirm it on the course, or keep the CRICOS total (the AI fee is withdrawn). ' || p_reason;
  perform set_config('cf.flag_fn', '1', true);
  insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source, kind, state, raised_by_kind, evidence)
  values ('course', f.course_id::text, v_c.provider_id, 'fee_ai_recheck', 'fee_crosscheck', left(v_why, 1000), 'fee-reader-recheck', 'hard', 'raised', 'person', v_ev)
  returning id into v_id;
  insert into pipeline.enrichment_flag_events(flag_id, action, actor, actor_kind, reason, evidence) values (v_id, 'raised', coalesce(p_actor, 'unknown'), 'person', left(v_why, 1000), v_ev);
  perform set_config('cf.flag_fn', '', true);
  return jsonb_build_object('fee_id', p_fee, 'raised', true, 'flag_id', v_id, 'course_id', f.course_id);
end $function$;
revoke all on function security.fee_admitted_recheck_v1(uuid, text, text) from public, anon, authenticated;
comment on function security.fee_admitted_recheck_v1(uuid, text, text) is 'CF-247 IQ-00111 D12: raise one "Fee fails the check" Layer 4 item to re-check an admitted AI fee, with its evidence and earlier decisions (new flag of field fee_ai_recheck; decided items are never changed). Service role or Platform Admin paste only.';

-- 3 a person's "Keep the CRICOS total" on a re-check item withdraws the AI fee it names --------------------------------------------------------
create or replace function security.fee_admitted_recheck_settle_tg() returns trigger
language plpgsql security definer set search_path to '' as $function$
-- CF-247 IQ-00111 D12: carries out a person's release of a fee_ai_recheck item ("Keep the CRICOS total"): the AI fee it names is withdrawn
-- through the fee status path when it is still the same active value; nothing else is touched. Off: fees.recheck_keep_withdraws_on 0.
declare v_fee uuid; v_n int := 0;
begin
  if new.release_kind is distinct from 'person' or security.pipeline_num_v1('fees.recheck_keep_withdraws_on', 1) < 1 then return null; end if;
  v_fee := case when new.evidence->>'fee_id' ~ '^[0-9a-f-]{36}$' then (new.evidence->>'fee_id')::uuid end;
  if v_fee is null then return null; end if;
  update catalogue.course_fees set status = 'inactive', valid_to = current_date, updated_at = now(),
         notes = coalesce(notes, '') || ' | Withdrawn ' || to_char(now(), 'YYYY-MM-DD') || ': Layer 4 re-check item ' || new.id || ' kept the CRICOS total (' || coalesce(new.released_by, 'a person') || ')'
   where id = v_fee and status = 'active' and fee_type = 'provider_current_tuition' and amount = (new.evidence->>'amount')::numeric
     and course_id::text = new.entity_key;
  get diagnostics v_n = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('fees', 'recheck_keep', 'catalogue.course_fees ' || left(v_fee::text, 8),
          jsonb_build_object('issue', 'IQ-00111', 'flag_id', new.id, 'fee_id', v_fee, 'withdrawn', v_n, 'released_by', new.released_by, 'release_reason', new.release_reason,
                             'why_not', case when v_n = 0 then 'the fee is no longer the same active value (confirmed or replaced on the course, or locked)' end), null);
  if v_n > 0 then
    perform scholarship.refresh_course_financial_calculations(new.entity_key::uuid, null);
    insert into search.refresh_requests(requested_by) values ('fee re-check ' || new.id);
  end if;
  return null;
end $function$;
revoke all on function security.fee_admitted_recheck_settle_tg() from public, anon, authenticated;
comment on function security.fee_admitted_recheck_settle_tg() is 'CF-247 IQ-00111 D12: when a person releases a fee_ai_recheck item (Keep the CRICOS total), the AI fee it names is withdrawn if still the same active value (fees.recheck_keep_withdraws_on).';
do $t$ begin
  if not exists (select 1 from pg_trigger where tgname = 'fee_admitted_recheck_settle' and tgrelid = 'pipeline.enrichment_flags'::regclass) then
    create trigger fee_admitted_recheck_settle after update of state on pipeline.enrichment_flags
      for each row when (new.field = 'fee_ai_recheck' and old.state = 'raised' and new.state = 'released')
      execute function security.fee_admitted_recheck_settle_tg();
  end if;
end $t$;

-- 4 the fee check card links its stored copy and carries a re-check's evidence --------------------------------------------------------------
select pg_temp.edit_once('security.layer4_inbox_items_v1()', 'a56bc3313e02ac0611deb5657da95ce0', 'c930125d7fda6efb4793b78eed0a10b5', array[
  array[$o$         jsonb_build_object('flag_id', f.id, 'course_id', c.id, 'course_code', c.course_code)
    from pipeline.enrichment_flags f left join catalogue.courses c on c.id::text = f.entity_key
$o$, $n$         jsonb_build_object('flag_id', f.id, 'course_id', c.id, 'course_code', c.course_code)
           -- CF-247 IQ-00111 D12: a fee check card links its stored copy (the flag's own, else the course page held) and carries a re-check's evidence
           || jsonb_strip_nulls(jsonb_build_object('evidence_id', fe.id, 'captured_at', fe.captured_at, 'source_url', fe.source_url,
                                                   'recheck', case when f.field = 'fee_ai_recheck' then f.evidence end))
    from pipeline.enrichment_flags f left join catalogue.courses c on c.id::text = f.entity_key
    left join lateral (select e.id, e.captured_at, e.source_url from pipeline.evidence_artifacts e
                        where f.reason_code = 'fee_crosscheck'
                          and e.id = coalesce(case when f.evidence->>'evidence_id' ~ '^[0-9a-f-]{36}$' then (f.evidence->>'evidence_id')::uuid end,
                                              (select g.evidence_id from pipeline.coverage_course_pages g where g.course_id = c.id))) fe on true
$n$]
], array[1]);

-- 5 remedy (workstream A's contract) and component register ---------------------------------------------------------------------------------
select security.ops_remedy_register_v1('fee_admitted_recheck', jsonb_build_object('title', 'Send an admitted AI fee that contradicts a fee check decision back to Layer 4',
  'treats', jsonb_build_array('fee_reader_hold_bypass'), 'authority', 'admin',
  'notes', 'security.fee_admitted_recheck_v1 through the governed paste docs/paste/PASTE-20261104-fee-admitted-recheck.sql; a person confirms the fee on the course or keeps the CRICOS total (the AI fee is withdrawn).'))
 where exists (select 1 from pipeline.ops_root_causes r where r.code = 'fee_reader_hold_bypass');

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.fee_admitted_recheck_v1', 'Layer 4', 'CF-247 IQ-00111 D12: raise a "Fee fails the check" item to re-check an admitted AI fee, with evidence and earlier decisions', 'active', '{}', '20261104180000'),
 ('function', 'security.fee_admitted_recheck_settle_tg', 'Layer 4', 'CF-247 IQ-00111 D12: Keep the CRICOS total on a re-check item withdraws the AI fee (trigger fee_admitted_recheck_settle)', 'active', '{}', '20261104180000')
on conflict do nothing;
