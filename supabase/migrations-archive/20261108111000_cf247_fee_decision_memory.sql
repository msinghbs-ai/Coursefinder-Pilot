-- CF-247 FEE lane (IQ-00040, P1): a person's ruling on a fee figure is not asked about again.
-- Why (live, read-only, 8 Nov 2026 ~03:20 UTC, project fxcwkweaxjtknorudmwp):
--   * 56 of the 136 pending provider_current_tuition_validation items in the Layer 4 Inbox (41%) were created AFTER a person had already decided
--     the same course: 55 after a rejection, 1 after an edited approval. 53 of the 56 propose the very amount the person decided on (a later
--     capture of the same page has a new evidence id, so the old "same page" check never matched). Oldest of them 27 Oct, newest 2 Nov.
--   * Cause: public.svc_fee_ai_record raises a new validation item whenever a read ends in review or conflict and no PENDING item exists; it never
--     looks at decided items (security.layer4_tuition_settle_v1 only supersedes pending duplicates and wrong-amount asks).
--   * Effect: reviewers are asked the same question again (Platform Admin's human capacity is the bottleneck for the fee queue).
-- What:
--   1 security.fee_reader_decided_v1(course, amount): the latest decided item (rejected, approved or edited_approved) of the course whose proposed
--     amount is within fees.decision_same_pct of this reading and that was decided within fees.decision_memory_days; null when the switch is off.
--   2 public.svc_fee_ai_record (md5-guarded edit): when such a ruling exists the read still ends as review (nothing is admitted, the figure is not
--     published), the row note says "a person already ruled on this figure (...); not raised again", and no new Layer 4 item is created. A different
--     amount, a ruling older than the memory, or the switch off behaves exactly as before.
--   3 Settings (G2): fees.respect_decisions_on 0 (ships OFF: the Controller switches it on after the first run is read), fees.decision_memory_days 90,
--     fees.decision_same_pct 1.
-- The 55 repeats already pending are not touched here (docs/paste/FEE-20261108-supersede-repeat-validation-items.md, Controller/Platform Admin).
-- A person is never replaced: no item is decided, approved or rejected; the only change is that an already-answered question is not put again.
-- Edited live function (md5 read live 8 Nov 2026 ~03:15 UTC, equal to the 4 Nov release 20261104140000; guarded both ways):
--   public.svc_fee_ai_record(uuid,jsonb,numeric,text) 5ec65e53403933b98381bd5c9c79b6d1 -> 90a9bfb569e6a1ff97e08f01ff20c855
-- Replaces: nothing (the earlier behaviour runs when fees.respect_decisions_on is 0)
-- Retires: nothing
-- Nothing is dropped or deleted. No consumer API object changes (G3). No AI or Firecrawl spend (it only suppresses a Layer 4 insert).

-- the edit helper (as 20261104140000): applies only to the definition it was written against, and checks the result
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

-- 1 settings (G2; Settings > Pipeline settings, section Enrichment beside the other fee reader settings) ---------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'fees.respect_decisions_on', 'Fee reader: do not ask again about a figure a person has ruled on',
  'On (1): when the AI fee reader reads the same figure for a course that a person already decided in Layer 4 (rejected, approved or edited), it records the read as review but does not raise a new fee check item. Off (0): it raises one whenever none is pending (the behaviour before 8 Nov 2026).',
  'number', to_jsonb(0), 0, 1, 'on/off', 360, 'Enrichment', 'public.svc_fee_ai_record; security.fee_reader_decided_v1',
  'IQ-00040 (8 Nov 2026): 56 of 136 pending fee checks repeat a decided question; ships off, the Controller switches it on after reading the first run'),
 ('pipeline', 'fees.decision_memory_days', 'Fee reader: how long a ruling on a figure is remembered',
  'A decided fee check blocks a repeat of the same figure for this many days; after that the figure is asked about again (fees change yearly).',
  'number', to_jsonb(90), 1, 400, 'days', 361, 'Enrichment', 'security.fee_reader_decided_v1', 'IQ-00040: a quarter, then a person looks again'),
 ('pipeline', 'fees.decision_same_pct', 'Fee reader: how close is the same figure',
  'A new reading counts as the figure a person decided on when it is within this share of the decided amount.',
  'number', to_jsonb(1), 0, 10, '%', 362, 'Enrichment', 'security.fee_reader_decided_v1', 'IQ-00040: rounding only (the repeats are identical amounts)')
on conflict (toolset_key, key) do nothing;

-- 2 the earlier ruling, if any -------------------------------------------------------------------------------------------------------------
create or replace function security.fee_reader_decided_v1(p_course uuid, p_amount numeric) returns jsonb
 language sql stable security definer set search_path to '' as $f$
  -- the latest ruling of a person on this figure for this course, or null (also null while fees.respect_decisions_on is 0)
  select jsonb_build_object('item', d.id, 'status', d.status, 'decided_at', d.decided_at, 'amount', (d.proposed_value->>'amount')::numeric)
    from pipeline.layer4_review_items d
   where security.pipeline_num_v1('fees.respect_decisions_on', 0) >= 1
     and d.entity_id = p_course and d.field_code = 'provider_current_tuition_validation' and d.status in ('rejected', 'approved', 'edited_approved')
     and d.decided_at > now() - make_interval(days => security.pipeline_num_v1('fees.decision_memory_days', 90)::int)
     and (d.proposed_value->>'amount') ~ '^[0-9]+(\.[0-9]+)?$'
     -- fixed: rounding floor of 1 (the reader's own tolerance for the same figure, as in svc_fee_ai_record)
     and abs((d.proposed_value->>'amount')::numeric - p_amount) <= greatest(1, p_amount * security.pipeline_num_v1('fees.decision_same_pct', 1) / 100.0)
   order by d.decided_at desc limit 1
$f$;
revoke execute on function security.fee_reader_decided_v1(uuid, numeric) from public, anon, authenticated;
comment on function security.fee_reader_decided_v1(uuid, numeric) is 'CF-247 IQ-00040: the latest Layer 4 ruling (rejected, approved, edited_approved) of a person on the same fee figure for a course within fees.decision_memory_days, or null; null while fees.respect_decisions_on is 0.';

-- 3 the reader's record: a ruled figure is not raised again --------------------------------------------------------------------------------
select pg_temp.edit_once('public.svc_fee_ai_record(uuid,jsonb,numeric,text)', '5ec65e53403933b98381bd5c9c79b6d1', '90a9bfb569e6a1ff97e08f01ff20c855', array[
  array[$o$declare v_held record; v_outcome text; v_note text;$o$,
        $n$declare v_held record; v_outcome text; v_note text; v_ruled jsonb;$n$],
  array[$o$      if v_outcome in ('review', 'conflict') and not exists (select 1 from pipeline.layer4_review_items l where l.entity_id = c.course_id$o$,
        $n$      -- CF-247 IQ-00040 (8 Nov 2026, fees.respect_decisions_on): a figure a person already ruled on in Layer 4 is recorded as review, not asked again
      v_ruled := case when v_outcome in ('review', 'conflict') then security.fee_reader_decided_v1(c.course_id, c.yearly) end;
      if v_ruled is not null then
        v_note := v_note || '; a person already ruled on this figure (' || (v_ruled->>'status') || ' ' || to_char((v_ruled->>'decided_at')::timestamptz, 'DD Mon YYYY')
                         || ', item ' || (v_ruled->>'item') || '); not raised again';
      end if;
      if v_outcome in ('review', 'conflict') and v_ruled is null and not exists (select 1 from pipeline.layer4_review_items l where l.entity_id = c.course_id$n$]],
  array[1, 1]);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'security.fee_reader_decided_v1', 'Layer 2', 'The Layer 4 ruling of a person on the same fee figure for a course (fee reader does not ask again)', 'active', '20261108111000')
on conflict (kind, name) do nothing;

do $post$
begin
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('fees.respect_decisions_on', 'fees.decision_memory_days', 'fees.decision_same_pct')) <> 3 then
    raise exception 'FEE decision memory post-check: settings';
  end if;
  if pg_get_functiondef('public.svc_fee_ai_record(uuid,jsonb,numeric,text)'::regprocedure) not like '%fee_reader_decided_v1%' then
    raise exception 'FEE decision memory post-check: svc_fee_ai_record not edited';
  end if;
end $post$;

select 'fee reader decision memory (off) in place' ok;
