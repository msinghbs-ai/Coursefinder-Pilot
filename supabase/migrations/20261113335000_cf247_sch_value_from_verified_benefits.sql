-- CF-247 F-SCH: the stated award value is filled from the version 3 reader's verified benefits (Platform Admin S2-Scholarship directive
-- 13 Nov 2026 14:50 §4 "complete required fields through the existing governed admission path"; Developer Requirements v2.26 F-SCH.13).
-- Why (live, 13 Nov 2026 04:10 UTC): 461 active scholarships are not published; 311 of them fail only or partly on "no stated award value"
--   (278 on that alone). The version 3 detail reader already verified a numeric benefit on the stored official page for 100 of the 278 and
--   recorded it in scholarship.coverage (amount with currency, or a tuition percentage, each with its quote), but nothing copies a verified
--   benefit into the canonical value (award_value_type, award_amount / award_percentage) that the publishing checks and the consumer read.
-- Change: security.scholarship_value_from_benefits_v1(scholarship) fills the canonical value once, only where it is empty (no type, or
--   text_only with no number), never over a manual lock, from that scholarship's own verified version 3 benefits:
--     a tuition percentage (full tuition = 100) first; otherwise the largest amount with a known currency of at least 50.
--   It records the change with the extraction, the quote and the rule in scholarship_sweep_changes. Publication policy is unchanged: the
--   existing scholarship-auto-publish run decides publication with the same checks (international audience, domestic-only, hand-check holds,
--   editions); nothing is published here.
--   security.scholarship_detail_apply_v1 calls it after the benefits are recorded, so new readings fill it the same way.
--   One backfill runs it for the active scholarships that already hold verified benefits and no value.
-- Replaces: security.scholarship_detail_apply_v1(bigint) (same name and signature; md5-guarded edit of the live text).
-- Retires: nothing.

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

create or replace function security.scholarship_value_from_benefits_v1(p_scholarship uuid)
returns text[] language plpgsql security definer set search_path to '' as $$
declare s record; b record;
begin
  select id, award_value_type, award_amount, award_percentage into s from scholarship.scholarships where id = p_scholarship and lifecycle_status = 'active';
  if s.id is null then return '{}'; end if;
  -- only an empty value: no type, or text_only with no number
  if s.award_value_type in ('percentage', 'fixed_amount') or coalesce(s.award_amount, s.award_percentage) is not null then return '{}'; end if;
  if exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = p_scholarship
               and k.field in ('award_value', 'award_value_type', 'award_amount', 'award_percentage')) then return '{}'; end if;
  -- the reader's verified benefits for this scholarship: a tuition percentage first, then the largest amount with a known currency
  select cv.coverage_type, cv.percentage, cv.amount, cv.currency_code, cv.notes, cv.evidence_id,
         (cv.notes like '% (maximum) %') is_max,
         nullif(substring(cv.notes from '^sch-extract-v3:([0-9]+)'), '')::bigint extraction_id
    into b
    from scholarship.coverage cv
   where cv.scholarship_id = p_scholarship and cv.notes like 'sch-extract-v3:%'
     and ((cv.coverage_type = 'tuition_fees' and cv.percentage > 0 and cv.percentage <= 100)
          or (cv.amount >= 50 and cv.currency_code is not null))  -- fixed: under 50 is a page placeholder (as the reader, 20261113066000)
   order by (cv.coverage_type = 'tuition_fees' and cv.percentage is not null) desc, cv.percentage desc nulls last, cv.amount desc nulls last
   limit 1;
  if b.coverage_type is null then return '{}'; end if;
  if b.coverage_type = 'tuition_fees' and b.percentage is not null then
    update scholarship.scholarships set award_value_type = 'percentage', award_percentage = b.percentage, award_applies_to_fee_type = coalesce(award_applies_to_fee_type, 'tuition'),
           award_value_is_maximum = coalesce(award_value_is_maximum, b.is_max), updated_at = now()
     where id = p_scholarship;
  else
    update scholarship.scholarships set award_value_type = 'fixed_amount', award_amount = b.amount, award_currency_code = b.currency_code,
           award_value_is_maximum = coalesce(award_value_is_maximum, b.is_max), updated_at = now()
     where id = p_scholarship;
  end if;
  insert into pipeline.scholarship_sweep_changes(scholarship_id, field, before_value, after_value, evidence_id)
  values (p_scholarship, 'award_value', jsonb_build_object('type', s.award_value_type),
          jsonb_build_object('by', 'sch-extract-v3', 'rule', 'value_from_verified_benefit', 'extraction', b.extraction_id, 'coverage_type', b.coverage_type,
                             'percentage', b.percentage, 'amount', b.amount, 'currency', b.currency_code, 'maximum', b.is_max, 'quote', left(b.notes, 600)),
          b.evidence_id);
  return array['award_value'];
end $$;
comment on function security.scholarship_value_from_benefits_v1(uuid) is
  'F-SCH 13 Nov 2026: fills an empty canonical award value once from the scholarship''s own verified version 3 benefits (tuition percentage first, then the largest amount with currency); never over a manual lock; publication still decided by scholarship-auto-publish.';
revoke all on function security.scholarship_value_from_benefits_v1(uuid) from public, anon, authenticated;

select pg_temp.edit_n('security.scholarship_detail_apply_v1(bigint)', 'a9288404514058b9d126baf5511b827d', array[
  array[$o$  v_done := v_done || security.scholarship_detail_extend_v1(e.id, s.id);  -- 20261113068000: award type, sponsor, rolling, benefits
$o$, $n$  v_done := v_done || security.scholarship_detail_extend_v1(e.id, s.id);  -- 20261113068000: award type, sponsor, rolling, benefits
  v_done := v_done || security.scholarship_value_from_benefits_v1(s.id);  -- 20261113335000: an empty stated value from the verified benefits
$n$]
], array[1]);

-- backfill: active scholarships that already hold verified version 3 benefits and no stated value
do $b$ declare r record; n int := 0; begin
  for r in select distinct cv.scholarship_id id from scholarship.coverage cv join scholarship.scholarships s on s.id = cv.scholarship_id
            where cv.notes like 'sch-extract-v3:%' and s.lifecycle_status = 'active' and coalesce(s.award_amount, s.award_percentage) is null
  loop
    if cardinality(security.scholarship_value_from_benefits_v1(r.id)) > 0 then n := n + 1; end if;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('scholarships', 'value_from_verified_benefits_backfill', 'scholarship.scholarships',
          jsonb_build_object('filled', n, 'migration', '20261113335000', 'directive', 'S2-Scholarship 13 Nov 2026 14:50 §4'), null);
  raise notice 'value filled for % scholarships', n;
end $b$;
