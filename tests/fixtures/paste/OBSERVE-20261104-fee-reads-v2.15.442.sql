-- CF-247 IQ-00111: observation of the first AI fee reads under v2.15.442 (migration 20261104140000). READ ONLY: safe at any time; run it as is.
-- Part 1: every fee_reader_rows row since 2026-11-03 10:52 UTC with its outcome, how its yearly figure was made, and whether its course had a hold.
-- Part 2: the check that must be 0: an AI fee admitted (active catalogue fee written by the reader) since then on a course with a raised fee check
-- hold or a fee-check exclusion (security.fee_reader_hold_v1), plus the reader's own integrity measure.
begin read only;
select x.created_at, c.course_code, left(coalesce(nullif(c.display_title, ''), c.canonical_title), 50) course, x.audience, x.amount_min, x.units_covered, x.units_kind,
       x.full_time_load, x.course_years, x.yearly, x.yearly_basis, x.yearly_method, x.yearly_how, x.yearly_hold, x.outcome, left(x.note, 160) note,
       security.fee_reader_hold_v1(x.course_id) hold_now,
       exists (select 1 from catalogue.course_fees f where f.course_id = x.course_id and f.fee_type = 'provider_current_tuition' and f.status = 'active'
                  and f.notes like '%AI fee reader (%' and f.created_at >= x.created_at - interval '1 minute') admitted_fee_active  -- fixed: same read
  from pipeline.fee_reader_rows x left join catalogue.courses c on c.id = x.course_id
 where x.created_at >= '2026-11-03 10:52:00+00' and x.outcome <> 'replaced'
 order by x.created_at, c.course_code;

select 'outcomes since 10:52 UTC' what, jsonb_object_agg(o, n) result
  from (select coalesce(outcome, 'null') o, count(*) n from pipeline.fee_reader_rows where created_at >= '2026-11-03 10:52:00+00' and outcome <> 'replaced' group by 1) z
union all
select 'methods since 10:52 UTC', jsonb_object_agg(m, n)
  from (select coalesce(yearly_method, 'earlier rule (no count)') m, count(*) n from pipeline.fee_reader_rows where created_at >= '2026-11-03 10:52:00+00' and outcome <> 'replaced' group by 1) z
union all
-- expected 0
select 'admitted while held (expected 0)', to_jsonb(count(*))
  from catalogue.course_fees f
 where f.fee_type = 'provider_current_tuition' and f.notes like '%AI fee reader (%' and f.created_at >= '2026-11-03 10:52:00+00'
   and (exists (select 1 from pipeline.enrichment_flags fl where fl.entity = 'course' and fl.entity_key = f.course_id::text and fl.field = 'fee' and fl.reason_code = 'fee_crosscheck'
                  and fl.flagged_at < f.created_at and (fl.state = 'raised' or fl.released_at > f.created_at))
        or exists (select 1 from pipeline.uni_adapter_exclusions e where e.course_id = f.course_id and e.field = 'fee' and e.active and e.set_at < f.created_at
                     and exists (select 1 from pipeline.enrichment_flags fl where fl.entity = 'course' and fl.entity_key = f.course_id::text and fl.field = 'fee' and fl.reason_code = 'fee_crosscheck')))
union all
select 'old unit division since 10:52 UTC (expected 0)', to_jsonb(count(*))
  from catalogue.course_fees f where f.fee_type = 'provider_current_tuition' and f.created_at >= '2026-11-03 10:52:00+00'
   and f.notes ~ 'for [0-9]+ points or credits \(a full-time year is [0-9]+\)'
union all
select 'integrity measure', security.fee_integrity_measure_v1();
rollback;
