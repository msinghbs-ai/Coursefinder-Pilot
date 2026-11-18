-- temporary probe (not for merge): timings of the coverage build's reads for one chunk, inside a rolled-back dry run
create or replace function pg_temp.prof() returns jsonb language plpgsql set search_path = pg_catalog, catalogue, pipeline, ref, security as $f$
declare t timestamptz; r jsonb := '{}'; v_chunk uuid[]; n bigint;
begin
  t:=clock_timestamp();
  create temp table _pc on commit drop as select co.provider_id, min(k.iso_alpha2::text) country_code, count(*) n from catalogue.courses co join catalogue.providers p on p.id=co.provider_id join ref.countries k on k.id=p.country_id where co.lifecycle_status='active' group by co.provider_id;
  r:=r||jsonb_build_object('pc',round(extract(epoch from clock_timestamp()-t)*1000)); t:=clock_timestamp();
  create temp table _cp on commit drop as select provider_id, min(computed_at) last_at from pipeline.course_attribute_coverage group by provider_id;
  r:=r||jsonb_build_object('cp',round(extract(epoch from clock_timestamp()-t)*1000)); t:=clock_timestamp();
  select array_agg(z.provider_id) into v_chunk from (select q.provider_id, sum(q.n) over (order by q.last_at nulls first, q.provider_id) run_n, row_number() over (order by q.last_at nulls first, q.provider_id) rn from (select pc.provider_id, pc.n, x.last_at from _pc pc left join _cp x on x.provider_id = pc.provider_id) q) z where z.rn = 1 or z.run_n <= 3000;
  create temp table _c on commit drop as select co.id course_id, co.provider_id from catalogue.courses co where co.lifecycle_status='active' and co.provider_id = any(v_chunk);
  analyze _c;
  r:=r||jsonb_build_object('chunk_c',round(extract(epoch from clock_timestamp()-t)*1000),'nc',(select count(*) from _c),'np',cardinality(v_chunk)); t:=clock_timestamp();
  perform count(*) from _pc t2 join catalogue.providers p on p.id=t2.provider_id where nullif(btrim(p.website),'') is not null or exists(select 1 from pipeline.provider_discovery_links l where l.provider_id=t2.provider_id);
  r:=r||jsonb_build_object('site',round(extract(epoch from clock_timestamp()-t)*1000)); t:=clock_timestamp();
  perform count(*) from (select distinct course_id from pipeline.layer2_course_discovery_candidates where selected and course_id is not null and course_id in (select course_id from _c)) x;
  r:=r||jsonb_build_object('found',round(extract(epoch from clock_timestamp()-t)*1000)); t:=clock_timestamp();
  perform count(*) from (select entity_id from pipeline.layer2_run_items where entity_type='course' and entity_id in (select course_id from _c) group by entity_id) x;
  r:=r||jsonb_build_object('read',round(extract(epoch from clock_timestamp()-t)*1000)); t:=clock_timestamp();
  perform count(*) from pipeline.coverage_course_pages where course_id in (select course_id from _c);
  r:=r||jsonb_build_object('sw',round(extract(epoch from clock_timestamp()-t)*1000)); t:=clock_timestamp();
  perform count(*) from pipeline.layer4_review_items where entity_type='course' and status='pending' and entity_id in (select course_id from _c);
  r:=r||jsonb_build_object('l4',round(extract(epoch from clock_timestamp()-t)*1000)); t:=clock_timestamp();
  perform count(*) from pipeline.layer3_work_items where entity_type='course' and entity_id in (select course_id from _c);
  r:=r||jsonb_build_object('l3',round(extract(epoch from clock_timestamp()-t)*1000)); t:=clock_timestamp();
  perform count(*) from (select distinct on (course_id, field) course_id from pipeline.field_enrich_items where course_id in (select course_id from _c) order by course_id, field, id desc) x;
  r:=r||jsonb_build_object('ei',round(extract(epoch from clock_timestamp()-t)*1000)); t:=clock_timestamp();
  perform count(*) from _c c cross join lateral (select distinct on (e.field) e.field, e.state from pipeline.field_enrich_items e where e.course_id = c.course_id order by e.field, e.id desc) x;
  r:=r||jsonb_build_object('ei_lat',round(extract(epoch from clock_timestamp()-t)*1000)); t:=clock_timestamp();
  perform count(*) from pipeline.course_field_absence a join pipeline.field_absence_classes k on k.code=a.absence_class where a.resolved_at is null and a.course_id in (select course_id from _c);
  r:=r||jsonb_build_object('ab',round(extract(epoch from clock_timestamp()-t)*1000)); t:=clock_timestamp();
  perform count(*) from _c c join pipeline.course_field_absence a on a.course_id = c.course_id join pipeline.field_absence_classes k on k.code=a.absence_class where a.resolved_at is null;
  r:=r||jsonb_build_object('ab_join',round(extract(epoch from clock_timestamp()-t)*1000)); t:=clock_timestamp();
  perform count(*) from catalogue.provider_entry_matrix m cross join lateral unnest(array_remove(array[m.study_level_id], null) || coalesce(security.entry_label_levels_v1(m.level_label), '{}'::uuid[])) x where m.status = 'active' and m.course_id is null and m.matrix_kind = 'provider_minimum' and m.min_grade is not null and m.grade_scale is distinct from 'none' and m.provider_id = any(v_chunk);
  r:=r||jsonb_build_object('aer_pm',round(extract(epoch from clock_timestamp()-t)*1000)); t:=clock_timestamp();
  perform count(*) from catalogue.provider_entry_matrix m where m.status = 'active' and m.course_id is not null and m.min_grade is not null and m.grade_scale is distinct from 'none' and m.course_id in (select course_id from _c);
  perform count(*) from catalogue.course_entry_requirements r2 where r2.status = 'active' and r2.kind = 'override' and r2.course_id in (select course_id from _c);
  r:=r||jsonb_build_object('aer_23',round(extract(epoch from clock_timestamp()-t)*1000)); t:=clock_timestamp();
  perform count(*) from _c c where exists(select 1 from catalogue.course_links l where l.course_id=c.course_id and l.status='active' and l.link_type='official_course')
     or exists(select 1 from catalogue.course_fees f where f.course_id=c.course_id and f.status='active')
     or exists(select 1 from catalogue.course_english_requirements e where e.course_id=c.course_id and e.status='active')
     or exists(select 1 from catalogue.course_intakes i where i.course_id=c.course_id)
     or exists(select 1 from catalogue.course_campuses cc join catalogue.campuses k on k.id=cc.campus_id where cc.course_id=c.course_id)
     or exists(select 1 from catalogue.course_academic_options a where a.course_id=c.course_id);
  r:=r||jsonb_build_object('val',round(extract(epoch from clock_timestamp()-t)*1000)); t:=clock_timestamp();
  delete from pipeline.course_attribute_coverage where provider_id = any(v_chunk);
  get diagnostics n = row_count;
  r:=r||jsonb_build_object('delete',round(extract(epoch from clock_timestamp()-t)*1000),'deleted',n); t:=clock_timestamp();
  return r;
end $f$;
