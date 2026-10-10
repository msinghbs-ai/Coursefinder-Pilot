create or replace function security.course_field_source_build_v1() returns jsonb
language plpgsql security definer set search_path = ''
as $f$
declare v_n int; v_t0 timestamptz := clock_timestamp();
begin
  create temp table _lk on commit drop as select * from security.course_field_lock_flags_v1();
  create temp table _fs on commit drop as
  select c.id course_id, c.provider_id, k.iso_alpha2::text cc,
    case when i.months is null then 'missing' when lk.li then 'hand' when i.calendar then 'central'
         when pg.evidence_id is not null and i.from_page then case when pg.candidates->>'intakes_by'='adapter' then 'adapter' else 'reader' end else 'other' end isrc,
    case when e.id is null then 'missing' when lk.le then 'hand' when e.source_requirement_key like 'policy:%' then 'central'
         when pg.evidence_id is not null and e.evidence_id=pg.evidence_id then case when pg.candidates->>'english_by'='adapter' then 'adapter' else 'reader' end else 'other' end esrc,
    case when f.id is null then 'missing' when lk.lf then 'hand'
         when pg.evidence_id is not null and f.evidence_id=pg.evidence_id then case when pg.candidates->>'fee_by'='adapter' then 'adapter' else 'reader' end else 'other' end fsrc
    from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries k on k.id=p.country_id
    left join pipeline.coverage_course_pages pg on pg.course_id=c.id left join _lk lk on lk.entity_id=c.id
    left join lateral (select array_agg(distinct x.intake_label) months, bool_or(coalesce(x.source_intake_key,'') like 'calendar%') calendar, bool_or(pg.evidence_id is not null and x.evidence_id=pg.evidence_id) from_page from catalogue.course_intakes x where x.course_id=c.id and x.status='active') i on true
    left join lateral (select r.id, r.source_requirement_key, r.evidence_id from catalogue.course_english_requirements r join ref.english_tests t on t.id=r.english_test_id where r.course_id=c.id and t.code='IELTS' and coalesce(r.status,'active')='active' order by r.last_verified_at desc nulls last limit 1) e on true
    left join lateral (select x.id, x.evidence_id from catalogue.course_fees x where x.course_id=c.id and x.status='active' and x.fee_type='provider_current_tuition' and x.audience='international' order by x.fee_year desc nulls last, x.updated_at desc nulls last limit 1) f on true
   where c.lifecycle_status='active';
  insert into pipeline.course_field_source (course_id, provider_id, country_code, tier, intakes_src, english_src, fee_src, computed_at)
  select s.course_id, s.provider_id, s.cc, (select x.tier from pipeline.course_attribute_coverage x where x.course_id=s.course_id limit 1), s.isrc, s.esrc, s.fsrc, now() from _fs s
  on conflict (course_id) do update set provider_id=excluded.provider_id, country_code=excluded.country_code, tier=excluded.tier, intakes_src=excluded.intakes_src, english_src=excluded.english_src, fee_src=excluded.fee_src, computed_at=excluded.computed_at;
  get diagnostics v_n = row_count;
  return jsonb_build_object('rows', v_n, 'ms', round(extract(epoch from clock_timestamp()-v_t0)*1000));
end $f$;
revoke all on function security.course_field_source_build_v1() from public, anon, authenticated;