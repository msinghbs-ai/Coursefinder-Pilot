-- CF-247 IQ-00111 (P0 fee integrity): the AI fee reader distinguishes units from credit points and uses the page's own full-time load, holds an
-- ambiguous yearly figure for a person instead of dividing, and never admits a page fee while a fee hold or a fee-check exclusion is active.
-- Authority: Layer 4 integrator handover 3 Nov 2026 (Priority 1, items 1-5), evidence recovery mandate 20:47 §2, upstream evidence audit 19:50
-- causes 3 and 4. Codes against workstream A's operations contract (20261104010000).
-- Why (live, read-only, 3 Nov 2026 20:49-21:40 AEDT):
--   * svc_fee_ai_record turns a fee "for N points or credits" into a yearly figure by N / pipeline.fee_country_profiles.full_time_units_a_year.
--     AU is 8 units (subjects), but the count on the page (or the one the model gives) is often credit points (Murdoch 24 a year, UNSW 48), VET
--     units of competency, or the whole course. 15 active rows carry "(a full-time year is 8)" with more than 8 points: 9 are wrong by this
--     defect (Murdoch 096011C 12,600 for a 37,800 one-year course; 6 UNSW graduate certificates 10,166.67-10,500 for 31,000-32,000 courses of
--     34-36 weeks; HELI 102291B 32,800 for 49,200 over 2 years; Reach 106655B 18,000 for 27,000 over 2 years), 3 VIT rows are right in units but
--     kept the domestic row, 3 are right. Website API v2 and Zoho returned the wrong figures (Rule 2 prefers the page fee over CRICOS).
--   * The reader admits without looking at fee holds. A fee_crosscheck hold writes an active fee exclusion; enqueue path b of
--     security.fee_course_pages_enqueue_v1 queues every course whose adapter fee is excluded, so the page was read a minute after the hold and
--     admitted a minute later (Murdoch: hold 14:19, queued 14:20, admitted 14:21 UTC 2 Nov; WSU 121432C: 06:19, 06:20, 06:21). 2 active AI rows
--     sit on raised holds; 149 courses carry a fee-check exclusion that a person decided ("the page figure is not an annual fee", "keep the
--     CRICOS total"; 088407E and 092696A since 19:36 3 Nov), 8 of them with an active AI row.
-- What:
--   1 security.fee_reader_yearly_v1(row, country, course): the yearly figure of a fee for a stated count, in this order: the page's own full-time
--     load (full_time_load, read by the model); else the country profile, only when the count is of the profile's kind (new column
--     fee_country_profiles.units_are: AU units, NZ and CA credit points); else the whole-course fee over the course length when that is a year or
--     more (page course_years, else the catalogue duration). The count is checked against the course length: a fee that covers more than a year
--     (or the whole course) whose implied years differ from the course length by more than fees.units_agreement_pct is held, and a fee with no
--     safe basis (a whole fee of a course shorter than a year with no load on the page; a count of unknown kind) is held. Held rows go to Layer 4
--     as "the per-year figure is not clear"; nothing is divided by a guess. Every row records how its figure was made (fee_reader_rows.yearly_how).
--   2 security.fee_reader_hold_v1(course): a raised fee_crosscheck hold, or an active fee exclusion from a fee-check decision (or, with
--     fees.respect_all_exclusions_on, any active fee exclusion). svc_fee_ai_record then records the course as held (no admission, no new Layer 4
--     item: the hold's own item or decision covers it); fee_course_pages_enqueue_v1 no longer queues such a course (path b) or a request for it
--     (path a, outcome held), so no AI read is spent on a page fee that cannot be admitted.
--   3 Settings (G2): fees.units_load_fix_on 1 (ships ON: a correctness fix, mandate "Behaviour changes are behind a setting; this one is a
--     correctness fix, so it ships ON"); fees.units_agreement_pct 20; fees.respect_holds_on 1 (ships ON: it only stops admissions that bypass a
--     person's hold, it admits nothing); fees.respect_all_exclusions_on 0 (ships OFF: extending it to every active fee exclusion would also stop the
--     designed AI second reading of adapter-excluded courses, 196 live rows such as Auckland; a Platform Admin decision); fees.integrity_max_attempts
--     and fees.integrity_cooldown_minutes for the verification remedy.
--   4 Worker (coverage-sweep v0.59.6, fees.ts): the model also returns units_kind, full_time_load, course_years and whole_course for each row.
--   5 AU profile note corrected (credit points are not units); root causes and remedies registered through A's contract; an auto verification
--     remedy that records whether any AI fee is active on a held course or was derived by the old division after this release.
-- Edited live functions (md5 read live 3 Nov 2026 21:2x AEDT; guarded both ways):
--   public.svc_fee_ai_record(uuid,jsonb,numeric,text) 0fb74c639ca69349ef18813282b0f987 -> 5ec65e53403933b98381bd5c9c79b6d1
--   security.fee_course_pages_enqueue_v1() 91b2591e44bf9755950619006bf78e32 -> 67b1b7db62dbd3c8e90053296f54a46a
-- Wrong values already active are not changed here: containment and correction are Platform Admin pastes (docs/paste/PASTE-20261104-fee-units-holds-*).
-- Replaces: the yearly-figure rule of public.svc_fee_ai_record for fees "for N points or credits" (N / profile load), switched off by
--   fees.units_load_fix_on 1 (the old rule still runs when it is 0)
-- Retires: nothing
-- Nothing is dropped or deleted. No consumer API object changes (G3): catalogue.course_fees is written only through the existing admission
-- path, and less often. No Firecrawl or AI spend (fewer AI reads: held courses are not queued).

-- 0 the contract this change codes against and the definitions it reads, unchanged since they were read live -------------------------------
do $g$
declare r record;
begin
  if to_regclass('pipeline.ops_remedies') is null then
    raise exception 'workstream A''s operations contract (migration 20261104010000) must be applied before this change';
  end if;
  for r in select * from (values ('security.fee_row_units_v1(jsonb)', '8d534a87af685cfd5d0d8a7bd54f6388'),
                                 ('security.uni_adapter_excluded(uuid,text)', '7359e28cc207833c658be6f169aa695c')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then
      raise exception 'live % differs from the definition this change was written against (md5 %)', r.sig, md5(pg_get_functiondef(r.sig::regprocedure)); end if;
  end loop;
end $g$;

-- the edit helper (copied from 20261103050000): applies only to the definition it was written against, and checks the result
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
 ('pipeline', 'fees.units_load_fix_on', 'Fee reader: read the full-time load from the page; hold unclear yearly figures',
  'On (1): a fee printed for a number of points, credits or units becomes a yearly figure only from the page''s own full-time load, the country''s load when the count is of the same kind (AU units, NZ and CA credit points), or the whole-course fee over the course length; a figure whose count disagrees with the course length, or that has no safe basis, goes to Layer 4 instead of being admitted. Off (0): the earlier rule (count / country load).',
  'number', to_jsonb(1), 0, 1, 'on/off', 350, 'Enrichment', 'public.svc_fee_ai_record; security.fee_reader_yearly_v1',
  'IQ-00111 (P0, 3 Nov 2026): correctness fix, ships on (integrator handover Priority 1 item 1)'),
 ('pipeline', 'fees.units_agreement_pct', 'Fee reader: count and course length may differ by',
  'A fee for a count that covers more than a year (or the whole course) implies a number of years; when that differs from the course length by more than this share, the yearly figure is held for a person.',
  'number', to_jsonb(20), 5, 100, '%', 351, 'Enrichment', 'security.fee_reader_yearly_v1',
  'IQ-00111: 1.5 implied years against a 2-year course (HELI 102291B, Reach 106655B) is 25% and must be held'),
 ('pipeline', 'fees.respect_holds_on', 'Fee reader: keep page fees out while a fee hold or fee-check exclusion is active',
  'On (1): the AI fee reader never admits a page fee for a course with a raised fee check hold or an active fee exclusion from a fee-check decision, and does not queue such a course for reading. Off (0): it admits regardless (the defect of 2 Nov 2026).',
  'number', to_jsonb(1), 0, 1, 'on/off', 352, 'Enrichment', 'public.svc_fee_ai_record; security.fee_course_pages_enqueue_v1; security.fee_reader_hold_v1',
  'IQ-00111 (P0, 3 Nov 2026): stops admissions that bypass a person''s hold; admits nothing; ships on (handover Priority 1 items 3-4)'),
 ('pipeline', 'fees.respect_all_exclusions_on', 'Fee reader: also keep page fees out for every active fee exclusion',
  'On (1): every active fee exclusion (pipeline.uni_adapter_exclusions, field fee) keeps the AI fee reader''s page fee out, not only exclusions from a fee-check decision. Off (0): an adapter fee excluded for another reason (semester totals, domestic panels, Auckland ranges) is still read again by the AI reader, as designed (196 active rows on 3 Nov 2026).',
  'number', to_jsonb(0), 0, 1, 'on/off', 353, 'Enrichment', 'security.fee_reader_hold_v1',
  'IQ-00111: ships off; changing what 1,585 non-fee-check exclusions mean is a Platform Admin decision'),
 ('pipeline', 'fees.integrity_max_attempts', 'Fee reader integrity check: attempts before a person is asked',
  'The operations controller checks again this many times that no AI fee is active on a held course or derived by the old division, before the issue needs a person.',
  'number', to_jsonb(3), 1, 10, 'attempts', 354, 'Enrichment', 'remedy fee_integrity_recheck (security.fee_integrity_verify_v1)', 'IQ-00111'),
 ('pipeline', 'fees.integrity_cooldown_minutes', 'Fee reader integrity check: wait between checks',
  'Minutes between two checks of the fee reader integrity remedy.',
  'number', to_jsonb(60), 10, 1440, 'minutes', 355, 'Enrichment', 'remedy fee_integrity_recheck', 'IQ-00111')
on conflict (toolset_key, key) do nothing;

-- 2 what each count is in each country, and how each yearly figure was made (new columns beside the reader's own tables) ------------------
alter table pipeline.fee_country_profiles add column if not exists units_are text check (units_are in ('units', 'credit_points'));
comment on column pipeline.fee_country_profiles.units_are is 'CF-247 IQ-00111: what full_time_units_a_year counts: units (subjects; AU) or credit_points (points or credits; NZ, CA). A fee for a count of the other kind is never divided by this load (security.fee_reader_yearly_v1).';
update pipeline.fee_country_profiles set units_are = case country_code when 'AU' then 'units' else 'credit_points' end
 where units_are is null and country_code in ('AU', 'NZ', 'CA');
update pipeline.fee_country_profiles
   set notes = 'Universities publish a yearly or per-unit fee; a full-time year is about 8 units (subjects). Credit points are not units and differ by university (24 a year at Murdoch, 48 units of credit at UNSW, 100 at Melbourne), and VET units of competency are not subjects, so a count of those is never a share of 8; give the page''s own full-time load when it states one.',
       reason = 'CF-247 IQ-00111 (3 Nov 2026): the earlier note equated 8 units with 48 credit points', updated_at = now()
 where country_code = 'AU' and notes = 'Universities publish a yearly or per-unit fee; a full-time year is about 8 units (48 credit points).';
alter table pipeline.fee_reader_rows add column if not exists units_kind text;
alter table pipeline.fee_reader_rows add column if not exists full_time_load numeric;
alter table pipeline.fee_reader_rows add column if not exists course_years numeric;
alter table pipeline.fee_reader_rows add column if not exists yearly_method text;
alter table pipeline.fee_reader_rows add column if not exists yearly_how text;
alter table pipeline.fee_reader_rows add column if not exists yearly_hold text;
comment on column pipeline.fee_reader_rows.yearly_method is 'CF-247 IQ-00111: how the yearly figure of a fee for a stated count was made: page_load, country_profile, course_length or published (held). Null: the earlier rule.';
comment on column pipeline.fee_reader_rows.yearly_hold is 'CF-247 IQ-00111: why the yearly figure is not clear (the row goes to Layer 4, never admitted). Null: clear.';
comment on column pipeline.fee_reader_rows.yearly_how is 'CF-247 IQ-00111: the sentence that explains the yearly figure (kept in the fee''s note).';

-- 3 the yearly figure of a fee for a stated count -------------------------------------------------------------------------------------------
create or replace function security.fee_reader_yearly_v1(p_row jsonb, p_country text, p_course uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 IQ-00111: null when the row is not a fee for a stated count (the earlier rules apply). Otherwise {yearly, basis, unit, method, how, hold,
-- units_kind, full_time_load, course_years}: the page's own load first, then the country load for a count of the country's kind, then the whole
-- fee over the course length (a year or more); the count is checked against the course length; no safe basis or a disagreement is a hold.
declare pr pipeline.fee_country_profiles%rowtype; v_units int := security.fee_row_units_v1(p_row); v_amt numeric := nullif(p_row->>'amount_min', '')::numeric;
        v_q text := coalesce(p_row->>'quote', ''); v_kind text; v_load numeric; v_years numeric; v_whole boolean; v_per numeric; v_method text; v_how text;
        v_hold text; v_implied numeric; v_tol numeric := security.pipeline_num_v1('fees.units_agreement_pct', 20) / 100.0; v_word text;
begin
  if coalesce(v_units, 0) <= 0 or coalesce(v_amt, 0) <= 0 then return null; end if;
  select * into pr from pipeline.fee_country_profiles where country_code = p_country;
  v_kind := case when p_row->>'units_kind' in ('units', 'credit_points') then p_row->>'units_kind'
                 when v_q ~* '(credit\s*points?|\mpoints?\M|\mcredits?\M|\muoc\M|\mcp\M)' then 'credit_points'
                 when v_q ~* '\m(units?|subjects?|modules?)\M' then 'units' end;
  v_word := coalesce(replace(v_kind, '_', ' '), 'points or units');
  v_load := case when nullif(p_row->>'full_time_load', '')::numeric > 0 then (p_row->>'full_time_load')::numeric end;
  v_years := case when nullif(p_row->>'course_years', '')::numeric > 0 then (p_row->>'course_years')::numeric end;
  if v_years is null then
    select case c.duration_unit when 'weeks' then c.duration_value / 52.0 when 'months' then c.duration_value / 12.0 when 'years' then c.duration_value end  -- fixed: calendar conversions
      into v_years from catalogue.courses c where c.id = p_course;
    if v_years <= 0 then v_years := null; end if;
  end if;
  v_whole := coalesce(case when p_row->>'whole_course' in ('true', 'false') then (p_row->>'whole_course')::boolean end, false)
          or v_q ~* '(\m(full|total|entire|whole)\M[^|]{0,40}\m(course|degree|program|programme|qualification)\M|\mto complete\M)';
  if v_load is not null then
    v_method := 'page_load'; v_per := v_amt / v_units * v_load;
    v_how := 'yearly figure from ' || v_amt || ' for ' || v_units || ' ' || v_word || ' (the page gives ' || v_load || ' a full-time year)';
  elsif v_kind is not null and v_kind = pr.units_are and pr.full_time_units_a_year > 0 then
    v_load := pr.full_time_units_a_year; v_method := 'country_profile'; v_per := v_amt / v_units * v_load;
    v_how := 'yearly figure from ' || v_amt || ' for ' || v_units || ' ' || v_word || ' (a full-time year is ' || v_load || ' ' || coalesce(pr.unit_name, v_word) || ')';
  elsif v_whole and v_years >= 1 then
    v_method := 'course_length'; v_per := v_amt / v_years;
    v_how := 'yearly figure from ' || v_amt || ' for the whole course over ' || round(v_years, 2) || ' years';
  end if;
  if v_load is not null then
    v_implied := v_units / v_load;
    if v_years is not null and (v_whole or v_implied > 1) and abs(v_implied - v_years) > v_tol * greatest(v_years, 1) then
      v_hold := v_units || ' ' || v_word || ' at ' || v_load || ' a year is ' || round(v_implied, 2) || ' years, but the course is ' || round(v_years, 2) || ' years';
      if v_years >= 1 then
        v_method := 'course_length'; v_per := v_amt / v_years;
        v_how := 'yearly figure from ' || v_amt || ' over the course length of ' || round(v_years, 2) || ' years';
      end if;
    end if;
  elsif v_per is null then
    v_hold := case when v_whole and v_years is not null
                   then v_amt || ' is the whole fee of a course of ' || round(v_years, 2) || ' years and the page gives no full-time load'
                   else 'the page does not say what the ' || v_units || ' ' || v_word || ' are or what a full-time year is' end;
    v_method := 'published'; v_per := v_amt;
    v_how := 'published figure ' || v_amt || ' for ' || v_units || ' ' || v_word || ', not converted';
  end if;
  return jsonb_build_object('yearly', round(v_per, 2),
    'basis', case when v_hold is null and v_load is not null and v_units = v_load then 'annual' else 'indicative_annual' end,
    'unit', case when v_hold is null and v_load is not null and v_units = v_load then 'per_year' else 'per_course' end,
    'method', v_method, 'how', v_how, 'hold', v_hold, 'units_kind', v_kind, 'full_time_load', v_load, 'course_years', round(v_years, 2));
end $function$;
revoke all on function security.fee_reader_yearly_v1(jsonb, text, uuid) from public, anon, authenticated;
comment on function security.fee_reader_yearly_v1(jsonb, text, uuid) is 'CF-247 IQ-00111: the yearly figure of an AI fee row for a stated count of points, credits or units, how it was made, and why it is held when it is not clear. Used by public.svc_fee_ai_record while fees.units_load_fix_on is on.';

-- 4 is a page fee kept out for this course ---------------------------------------------------------------------------------------------------
create or replace function security.fee_reader_hold_v1(p_course uuid) returns text
language sql stable security definer set search_path to '' as $function$
  -- CF-247 IQ-00111: why the AI fee reader may not admit a page fee for this course now, or null. A raised fee check hold (Layer 4 decides); an
  -- active fee exclusion from a fee-check decision (the person decided the page figure is not the annual fee, e.g. "keep the CRICOS total");
  -- any active fee exclusion while fees.respect_all_exclusions_on is on.
  select case
    when exists (select 1 from pipeline.enrichment_flags fl where fl.entity = 'course' and fl.entity_key = p_course::text and fl.field = 'fee'
                    and fl.reason_code = 'fee_crosscheck' and fl.state = 'raised')
      then 'a fee check hold is raised for this course; Layer 4 decides'
    when exists (select 1 from pipeline.uni_adapter_exclusions e where e.course_id = p_course and e.field = 'fee' and e.active)
     and exists (select 1 from pipeline.enrichment_flags fl where fl.entity = 'course' and fl.entity_key = p_course::text and fl.field = 'fee' and fl.reason_code = 'fee_crosscheck')
      then 'the page fee is excluded for this course by a fee check decision'
    when security.pipeline_num_v1('fees.respect_all_exclusions_on', 0) >= 1
     and exists (select 1 from pipeline.uni_adapter_exclusions e where e.course_id = p_course and e.field = 'fee' and e.active)
      then 'the page fee is excluded for this course'
  end
$function$;
revoke all on function security.fee_reader_hold_v1(uuid) from public, anon, authenticated;
comment on function security.fee_reader_hold_v1(uuid) is 'CF-247 IQ-00111: the reason the AI fee reader keeps a page fee out for a course (raised fee check hold, fee-check exclusion, or any fee exclusion with fees.respect_all_exclusions_on), or null.';

-- 5 the reader: the new yearly rule, ambiguous figures to Layer 4, holds respected ----------------------------------------------------------
select pg_temp.edit_once('public.svc_fee_ai_record(uuid,jsonb,numeric,text)', '0fb74c639ca69349ef18813282b0f987', '5ec65e53403933b98381bd5c9c79b6d1', array[
  array[$o$        v_max int := security.pipeline_num_v1('fees.max_pages_per_provider', 12)::int; v_notes text; v_x record;
$o$, $n$        v_max int := security.pipeline_num_v1('fees.max_pages_per_provider', 12)::int; v_notes text; v_x record;
        -- CF-247 IQ-00111: the yearly figure of a fee for a stated count (fees.units_load_fix_on) and fee holds (fees.respect_holds_on)
        v_rid uuid; v_y jsonb; v_fix boolean := security.pipeline_num_v1('fees.units_load_fix_on', 1) >= 1;
        v_respect boolean := security.pipeline_num_v1('fees.respect_holds_on', 1) >= 1; v_hold text;
$n$],
  array[$o$           'pending', security.fee_row_units_v1(r);
$o$, $n$           'pending', security.fee_row_units_v1(r)
    returning id into v_rid;
    -- CF-247 IQ-00111: a fee for a stated count is made yearly from the page's own load, the country load for a count of its kind, or the course
    -- length; a figure that is not clear is kept with its reason and goes to Layer 4
    if v_fix then
      v_y := security.fee_reader_yearly_v1(r, v_cc, (select x.course_id from pipeline.fee_reader_rows x where x.id = v_rid));
      if v_y is not null then
        update pipeline.fee_reader_rows set yearly = (v_y->>'yearly')::numeric, yearly_basis = v_y->>'basis', unit = v_y->>'unit', yearly_method = v_y->>'method',
               yearly_how = v_y->>'how', yearly_hold = v_y->>'hold', units_kind = v_y->>'units_kind', full_time_load = (v_y->>'full_time_load')::numeric,
               course_years = (v_y->>'course_years')::numeric
         where id = v_rid;
      end if;
    end if;
$n$],
  array[$o$(array_agg(x.units_covered order by x.yearly))[1] units
$o$, $n$(array_agg(x.units_covered order by x.yearly))[1] units,
           string_agg(distinct x.yearly_hold, '; ') hold, (array_agg(x.yearly_how order by x.yearly))[1] how
$n$],
  array[$o$             || case when c.units is not null and c.units <> pr.full_time_units_a_year
$o$, $n$             || case when c.how is not null then c.how || '; '
                     when c.units is not null and c.units <> pr.full_time_units_a_year
$n$],
  array[$o$        else 'review' end;
$o$, $n$        else 'review' end;
      -- CF-247 IQ-00111: a yearly figure that is not clear is never admitted; a page fee is never admitted while a fee hold or fee-check exclusion is active
      if c.hold is not null and v_outcome <> 'same' then
        if v_outcome = 'admitted' then v_outcome := 'review'; end if;
        v_note := v_note || '; per-year figure not clear: ' || c.hold;
      end if;
      v_hold := case when v_respect and v_outcome <> 'same' then security.fee_reader_hold_v1(c.course_id) end;
      if v_hold is not null then v_outcome := 'held'; v_note := v_note || '; not admitted: ' || v_hold; end if;
$n$],
  array[$o$                case when v_outcome = 'conflict' then 'Fee reader: a different fee is held from another source'
$o$, $n$                case when v_outcome = 'conflict' then 'Fee reader: a different fee is held from another source'
                     when c.hold is not null then 'Fee reader: the per-year figure is not clear'
$n$]
], array[1, 1, 1, 1, 1, 1]);

-- 6 the reader's queue: no AI read is spent on a course whose page fee cannot be admitted ----------------------------------------------------
select pg_temp.edit_once('security.fee_course_pages_enqueue_v1()', '91b2591e44bf9755950619006bf78e32', '67b1b7db62dbd3c8e90053296f54a46a', array[
  array[$o$    v_hash := coalesce(rq.content_hash, rq.evidence_id::text);
$o$, $n$    -- CF-247 IQ-00111: a request for a course whose page fee is kept out (fee hold or fee-check exclusion) is closed as held, not read
    if security.pipeline_num_v1('fees.respect_holds_on', 1) >= 1 and security.fee_reader_hold_v1(rq.course_id) is not null then
      update pipeline.fee_course_requests set queued_at = now(), outcome = 'held' where course_id = rq.course_id;
      continue;
    end if;
    v_hash := coalesce(rq.content_hash, rq.evidence_id::text);
$n$],
  array[$o$     and security.coverage_identity_allowed(g.provider_id, g.identity_basis, 'tuition')
     and not exists (select 1 from catalogue.course_fees f$o$, $n$     and security.coverage_identity_allowed(g.provider_id, g.identity_basis, 'tuition')
     and not (security.pipeline_num_v1('fees.respect_holds_on', 1) >= 1 and security.fee_reader_hold_v1(g.course_id) is not null)  -- CF-247 IQ-00111
     and not exists (select 1 from catalogue.course_fees f$n$]
], array[1, 1]);

-- 7 the verification the operations controller runs (records only) --------------------------------------------------------------------------
create or replace function security.fee_integrity_measure_v1() returns jsonb
language sql stable security definer set search_path to '' as $function$
  -- CF-247 IQ-00111: active AI fee rows on a course whose page fee is kept out, and active AI fee rows made by the old count / country-load rule
  -- for a count above the load after this release (both should be 0 once the release is live and the containment paste has run); rows the
  -- reader held and rows whose yearly figure was not clear
  select jsonb_build_object(
    'ai_active_on_held', (select count(*) from catalogue.course_fees f where f.fee_type = 'provider_current_tuition' and f.status = 'active'
                            and f.notes like '%AI fee reader (%' and security.fee_reader_hold_v1(f.course_id) is not null
                            and (security.fee_reader_hold_v1(f.course_id) like 'a fee check hold%'
                                 or exists (select 1 from pipeline.uni_adapter_exclusions e where e.course_id = f.course_id and e.field = 'fee' and e.active and e.set_at < f.created_at))),
    'ai_old_division_since_release', (select count(*) from catalogue.course_fees f join pipeline.component_register g on g.kind = 'function' and g.name = 'security.fee_reader_yearly_v1'
                            where f.fee_type = 'provider_current_tuition' and f.status = 'active' and f.created_at > g.registered_at
                              and f.notes ~ 'for [0-9]+ points or credits \(a full-time year is [0-9]+\)'),
    'held_rows', (select count(*) from pipeline.fee_reader_rows x where x.outcome = 'held'),
    'unclear_rows', (select count(*) from pipeline.fee_reader_rows x where x.yearly_hold is not null and x.outcome <> 'replaced'))
$function$;
revoke all on function security.fee_integrity_measure_v1() from public, anon, authenticated;
comment on function security.fee_integrity_measure_v1() is 'CF-247 IQ-00111: fee reader integrity measure (AI fees active on held courses; old-rule divisions after the release; held and unclear rows in 7 days). Read only.';

create or replace function security.fee_integrity_recheck_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path to '' as $function$
  -- CF-247 IQ-00111 remedy fee_integrity_recheck: measures only; it changes nothing (wrong values are withdrawn by a Platform Admin paste)
  select jsonb_build_object('ok', true, 'changed', false, 'evidence', security.fee_integrity_measure_v1())
$function$;
create or replace function security.fee_integrity_verify_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path to '' as $function$
  select jsonb_build_object('passed', (m->>'ai_active_on_held')::int = 0 and (m->>'ai_old_division_since_release')::int = 0, 'measure', m,
         'evidence', jsonb_build_array('security.fee_integrity_measure_v1()'))
    from (select security.fee_integrity_measure_v1() m) z
$function$;
revoke all on function security.fee_integrity_recheck_v1(bigint) from public, anon, authenticated;
revoke all on function security.fee_integrity_verify_v1(bigint) from public, anon, authenticated;

-- 8 root causes and remedies (workstream A's contract) ---------------------------------------------------------------------------------------
select security.ops_root_cause_register_v1(x.code, x.spec) from (values
 ('fee_reader_units_misread', jsonb_build_object('class', 'rule', 'title', 'The AI fee reader divided a fee for credit points or a whole course by the country''s unit load',
   'description', 'A fee printed for N points, credits or units became N / pipeline.fee_country_profiles.full_time_units_a_year years. AU is 8 units (subjects); credit points (24 a year at Murdoch, 48 at UNSW), VET units of competency and whole-course counts are not. Live 3 Nov 2026: 9 active wrong rows visible to Website API v2 and Zoho (Murdoch 096011C 12,600 for 37,800; 6 UNSW graduate certificates about 10,333 for 31,000). Fixed by security.fee_reader_yearly_v1 (fees.units_load_fix_on); wrong active values are withdrawn by a Platform Admin paste.',
   'detect', jsonb_build_object('priority', 46, 'confidence', 0.9, 'any', jsonb_build_array(jsonb_build_object('fingerprint_like', jsonb_build_array('fee:ai\_reader\_credit\_point\_unit%', 'fee:ai\_reader\_units%'))),
                                'route', 'needs_release', 'recommend', 'Release 20261104140000 (fee reader units and holds); withdraw the wrong active values by the containment paste; correct them by the correction paste.'))),
 ('fee_reader_hold_bypass', jsonb_build_object('class', 'rule', 'title', 'The AI fee reader admitted a page fee while a fee hold or fee-check exclusion was active',
   'description', 'svc_fee_ai_record admitted without looking at fee holds, and the fee check''s own exclusion queued the course page for the reader (enqueue path b), so the page fee went live a minute after the hold (Murdoch 096011C, WSU 121432C on 2 Nov 2026). Fixed by security.fee_reader_hold_v1 (fees.respect_holds_on).',
   'detect', jsonb_build_object('priority', 47, 'confidence', 0.9, 'any', jsonb_build_array(jsonb_build_object('fingerprint_like', jsonb_build_array('fee:ai\_reader\_hold%'))),
                                'route', 'needs_release', 'recommend', 'Release 20261104140000; withdraw AI fees active on raised holds by the containment paste.')))
) x(code, spec);

select security.ops_remedy_register_v1(x.code, x.spec) from (values
 ('fee_integrity_recheck', jsonb_build_object('title', 'Check that no AI fee is active on a held course or made by the old unit division',
   'treats', jsonb_build_array('fee_reader_units_misread', 'fee_reader_hold_bypass'), 'authority', 'auto',
   'action_fn', 'security.fee_integrity_recheck_v1(bigint)', 'verify_fn', 'security.fee_integrity_verify_v1(bigint)',
   'max_attempts_key', 'fees.integrity_max_attempts', 'cooldown_key', 'fees.integrity_cooldown_minutes',
   'notes', 'Measures only (security.fee_integrity_measure_v1). It passes once the release is live and the containment paste has run.')),
 ('fee_reader_units_holds_release', jsonb_build_object('title', 'Release the fee reader units and holds fix (migration 20261104140000, worker v0.59.6)',
   'treats', jsonb_build_array('fee_reader_units_misread', 'fee_reader_hold_bypass'), 'authority', 'release')),
 ('fee_wrong_value_withdraw', jsonb_build_object('title', 'Platform Admin: withdraw wrong active fee values by paste, then correct them through the governed path',
   'treats', jsonb_build_array('fee_reader_units_misread', 'fee_reader_hold_bypass'), 'authority', 'admin',
   'notes', 'docs/paste/PASTE-20261104-fee-units-holds-containment.sql (13 rows; rollback beside it); correction paste PASTE-20261104-fee-units-holds-correction.sql. Manual values are never touched.'))
) x(code, spec);

-- 9 component register --------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.fee_reader_yearly_v1', 'Layer 3', 'CF-247 IQ-00111: yearly figure of an AI fee for a stated count (page load, country load of the same kind, course length; unclear held)', 'active', '{}', '20261104140000'),
 ('function', 'security.fee_reader_hold_v1', 'Layer 3', 'CF-247 IQ-00111: why the AI fee reader keeps a page fee out (fee hold, fee-check exclusion)', 'active', '{}', '20261104140000'),
 ('function', 'security.fee_integrity_measure_v1', 'Layer 3', 'CF-247 IQ-00111: fee reader integrity measure', 'active', '{}', '20261104140000'),
 ('function', 'security.fee_integrity_recheck_v1', 'Layer 3', 'CF-247 IQ-00111: remedy fee_integrity_recheck (measures only)', 'active', '{}', '20261104140000'),
 ('function', 'security.fee_integrity_verify_v1', 'Layer 3', 'CF-247 IQ-00111: verification of remedy fee_integrity_recheck', 'active', '{}', '20261104140000')
on conflict do nothing;
