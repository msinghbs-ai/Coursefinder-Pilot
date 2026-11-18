-- CF-247 (22 Oct 2026). Platform Admin 14:35: "proceed with AUT fee fix".
-- Found in the NZ review data: a fee printed for a stated number of points, such as AUT's "$19,929.84 (for 60 points)" or Lincoln and
-- Canterbury's "$27,300 (60 points)", was read as a fee PER point and multiplied by a full-time year (120), giving NZ$2.4-3.4 million a
-- year (51 rows, held in Layer 4 by the range check, nothing published). The same wording read as "per course" had no yearly figure at
-- all (52 rows "not a yearly fee").
-- Fix:
--   1 security.fee_row_units_v1(row): how many points or credits a row's amount covers, taken from the quote itself when the amount is
--     followed by "(60 points)" or "for 60 points" (not when the quote says "per point"), or from the reader's own units_covered when
--     it calls the row a whole-course fee. Deterministic: the quote is on the page, so the number is too.
--   2 svc_fee_ai_record: a row with units covered gets yearly = amount / units x the country's full-time load (NZ 120 points), unit
--     per_year when it covers exactly a full-time year, otherwise per_course with an indicative yearly figure; the note says
--     "yearly figure from 19929.84 for 60 points". The row keeps units_covered. When the reader had called it per point or per credit,
--     a finding (fee unit not understood) is recorded with the quote and what it really is, so the provider's next read is told about it.
--   3 A page read again replaces its earlier rows (they stay, outcome replaced) instead of being mixed with the new ones.
--   4 The 8 fee pages with these rows (AUT, Lincoln, Canterbury) are queued to be read again.
-- Replaces: public.svc_fee_ai_record (units covered, replaced rows). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266): fees reach courses only through security.coverage_apply_course_v1 as before.

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

alter table pipeline.fee_reader_rows add column if not exists units_covered int;
comment on column pipeline.fee_reader_rows.units_covered is 'CF-247 22 Oct 2026: points or credits the amount is for, when the page says so ("$19,929.84 (for 60 points)"); the yearly figure is amount / units x the country''s full-time load.';

-- 1 ---------------------------------------------------------------------------------------------------------------------------------
create or replace function security.fee_row_units_v1(p_row jsonb) returns int
language sql immutable set search_path = '' as $function$
  -- CF-247 22 Oct 2026: points or credits a fee row's amount is for, from the quote ("$19,929.84 (for 60 points)", "$27,300 (60 points)",
  -- "$41,859.67 for 120 credits"); never for a per-term row or a quote that says per point / per credit / per paper
  select case
    when coalesce(p_row->>'unit', '') = 'per_term' then null
    when coalesce(p_row->>'quote', '') ~* '(\m(per|each)\s+(point|credit|paper)\M|/\s*(point|credit|paper)\M)' then null
    else nullif(coalesce(
      (select m[1]::int from regexp_match(coalesce(p_row->>'quote', ''), '\d[\d,]*(?:\.\d{1,2})?\s*\(\s*(?:for\s+)?(\d{1,3})\s*(?:points?|credits?|pts)\M', 'i') m),
      (select m[1]::int from regexp_match(coalesce(p_row->>'quote', ''), '\d[\d,]*(?:\.\d{1,2})?\s+for\s+(\d{1,3})\s*(?:points?|credits?|pts)\M', 'i') m),
      case when p_row->>'unit' = 'per_course' and coalesce(p_row->>'units_covered', '') ~ '^\d{1,3}(\.0+)?$' then (p_row->>'units_covered')::numeric::int end), 0)
  end
$function$;
comment on function security.fee_row_units_v1(jsonb) is 'CF-247 22 Oct 2026: points or credits a fee row''s amount covers, from its quote or the reader''s units_covered for a whole-course fee; null when not stated.';
revoke all on function security.fee_row_units_v1(jsonb) from public;

-- 2 and 3 ---------------------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('public.svc_fee_ai_record(uuid,jsonb,numeric,text)', 'b34253b9806cfb1b6d0aa14992412250', array[
  [$o$  -- 1 each row as published, its yearly figure and its course
  for r in select$o$,
   $n$  -- 1 each row as published, its yearly figure and its course
  -- 22 Oct 2026: a page read again replaces its earlier rows (kept, outcome replaced), so old and new readings are never mixed
  update pipeline.fee_reader_rows set outcome = 'replaced' where queue_id = q.id;
  for r in select$n$],
  [$o$title_similarity, outcome)$o$, $n$title_similarity, outcome, units_covered)$n$],
  [$o$upper(coalesce(r->>'currency', v_cur)), coalesce(r->>'unit', 'unknown'),$o$,
   $n$upper(coalesce(r->>'currency', v_cur)),
           -- 22 Oct 2026: a fee for a stated number of points is per_year when that is a full-time year, otherwise per_course
           case when security.fee_row_units_v1(r) > 0 then case when security.fee_row_units_v1(r) = pr.full_time_units_a_year then 'per_year' else 'per_course' end
                else coalesce(r->>'unit', 'unknown') end,$n$],
  [$o$           case coalesce(r->>'unit', 'unknown')
             when 'per_year' then nullif(r->>'amount_min', '')::numeric$o$,
   $n$           case when security.fee_row_units_v1(r) > 0 and pr.full_time_units_a_year > 0
                then round(nullif(r->>'amount_min', '')::numeric / security.fee_row_units_v1(r) * pr.full_time_units_a_year, 2) else
           case coalesce(r->>'unit', 'unknown')
             when 'per_year' then nullif(r->>'amount_min', '')::numeric$n$],
  [$o$             when 'per_term' then nullif(r->>'amount_min', '')::numeric * pr.terms_a_year end,$o$,
   $n$             when 'per_term' then nullif(r->>'amount_min', '')::numeric * pr.terms_a_year end end,$n$],
  [$o$           case coalesce(r->>'unit', 'unknown') when 'per_year' then 'annual' when 'per_credit' then 'indicative_annual' when 'per_point' then 'indicative_annual'
                when 'per_term' then 'indicative_annual' end,$o$,
   $n$           case when security.fee_row_units_v1(r) > 0 then case when security.fee_row_units_v1(r) = pr.full_time_units_a_year then 'annual' else 'indicative_annual' end else
           case coalesce(r->>'unit', 'unknown') when 'per_year' then 'annual' when 'per_credit' then 'indicative_annual' when 'per_point' then 'indicative_annual'
                when 'per_term' then 'indicative_annual' end end,$n$],
  [$o$           'pending';
  end loop;$o$,
   $n$           'pending', security.fee_row_units_v1(r);
    if security.fee_row_units_v1(r) > 0 and r->>'unit' in ('per_point', 'per_credit') then
      perform security.fee_reader_finding_v1(q.provider_id, q.fact_source_id, 'unit_unknown', left(coalesce(r->>'qualification', '') || ' ' || coalesce(r->>'subject', ''), 300),
        jsonb_build_object('quote', left(r->>'quote', 200), 'read_as', r->>'unit', 'is', 'the fee for ' || security.fee_row_units_v1(r) || ' points or credits, not a fee per point', 'url', f.url));
    end if;
  end loop;$n$],
  [$o$   where x.queue_id = q.id;
  for v_x in select$o$,
   $n$   where x.queue_id = q.id and x.outcome = 'pending';
  for v_x in select$n$],
  [$o$(array_agg(x.amount_min order by x.yearly))[1] published
$o$,
   $n$(array_agg(x.amount_min order by x.yearly))[1] published, (array_agg(x.units_covered order by x.yearly))[1] units
$n$],
  [$o$|| case when c.basis = 'indicative_annual' then 'yearly estimate from '$o$,
   $n$|| case when c.units is not null and c.units <> pr.full_time_units_a_year
                     then 'yearly figure from ' || c.published || ' for ' || c.units || ' points or credits (a full-time year is ' || pr.full_time_units_a_year || '); '
                     when c.basis = 'indicative_annual' then 'yearly estimate from '$n$]
]);

-- 4 ---------------------------------------------------------------------------------------------------------------------------------
update pipeline.fee_reader_queue set state = 'queued', attempts = 0, leased_until = null, error = null
 where id in (select distinct r.queue_id from pipeline.fee_reader_rows r
               where (r.unit in ('per_point', 'per_credit') and r.outcome = 'review' and security.fee_row_units_v1(jsonb_build_object('unit', r.unit, 'quote', r.quote)) > 0)
                  or (r.unit = 'per_course' and r.outcome = 'not_yearly' and security.fee_row_units_v1(jsonb_build_object('unit', r.unit, 'quote', r.quote)) > 0));
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('fees', 'read_again', 'units_covered_fix', jsonb_build_object('reason', 'CF-247 22 Oct 2026: fees printed for a number of points were read as per point'), null);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.fee_row_units_v1', 'Layer 2', 'Fee reader: points or credits a fee row covers, from its quote', 'active', '{}', '20261022021000')
on conflict (kind, name) do nothing;
