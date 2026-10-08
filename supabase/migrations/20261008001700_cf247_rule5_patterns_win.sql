-- CF-247 Standing Review Rule 5, model and patterns disagree (8 Oct 2026, Platform Admin, multiple choice "Patterns win, no review").
-- Where the value held for a course is the Layer 3 model's reading (its latest validated interpretation) and the course's university
-- adapter read a different value with its own patterns, the adapter's reading replaces it, with no Layer 4 item, even when that field
-- is not admitted for the adapter. Measured on 8 Oct: intakes 952 of 7,099 courses compared differ (120 providers), English 16 of
-- 3,907, fee 27 of 698; in almost all of them the model reading is the older one.
-- Done inside security.adapter_overwrite_v1 (every 10 minutes), patched behind an md5 guard and exact anchors:
--   * pages of switched-on adapters are considered when the adapter admits or the course has a validated Layer 3 reading;
--   * a field is written when the adapter admits it (as before) or when the held value equals the latest Layer 3 reading (Rule 5);
--   * delivery mode is still written only for admitting adapters.
-- Unchanged: values entered or locked by hand are never touched, per-course exclusions stay, identity checks stay, every change is
-- logged in pipeline.adapter_overwrite_changes and pending review items on the same field are closed.
do $p$
declare d text;
begin
  d := pg_get_functiondef('security.adapter_overwrite_v1(int)'::regprocedure);
  if md5(d) <> '055cb7b44c3b42341e2b14f43488f026' then raise exception 'adapter_overwrite_v1 is not the version this migration expects'; end if;
  if (select count(*) from regexp_matches(d, 'join pipeline\.uni_adapters u on u\.provider_id = pg\.provider_id and u\.enabled and u\.admit\n', 'g')) <> 1
     or (select count(*) from regexp_matches(d, 'cur_fee\n      from pipeline', 'g')) <> 1
     or (select count(*) from regexp_matches(d, '''intakes'' = any \(r\.af\)', 'g')) <> 1
     or (select count(*) from regexp_matches(d, '''english'' = any \(r\.af\)', 'g')) <> 1
     or (select count(*) from regexp_matches(d, '''fee'' = any \(r\.af\)', 'g')) <> 1
     or (select count(*) from regexp_matches(d, '''delivery'' = any \(r\.af\)', 'g')) <> 1 then
    raise exception 'an anchor was not found exactly once';
  end if;
  d := replace(d, E'join pipeline.uni_adapters u on u.provider_id = pg.provider_id and u.enabled and u.admit\n',
    E'join pipeline.uni_adapters u on u.provider_id = pg.provider_id and u.enabled\n'
    || E'       and (u.admit or exists (select 1 from pipeline.layer3_interpretations l3 where l3.entity_type = ''course'' and l3.entity_id = pg.course_id and l3.status = ''validated''\n'
    || E'                                and l3.task_class in (''provider_intake_validation'', ''provider_english_validation'', ''provider_current_tuition_validation'')))\n');
  d := replace(d, E'cur_fee\n      from pipeline',
    E'cur_fee,\n'
    || E'           u.admit adm,\n'
    || E'           (select (select array_agg(distinct z::int order by z::int) from jsonb_array_elements_text(l.cv->''months'') z)\n'
    || E'                   = (select array_agg(distinct extract(month from to_date(i.intake_label, ''Month''))::int order by extract(month from to_date(i.intake_label, ''Month''))::int)\n'
    || E'                        from catalogue.course_intakes i where i.course_id = pg.course_id and i.status = ''active'' and i.intake_label ~ ''^(January|February|March|April|May|June|July|August|September|October|November|December)$'')\n'
    || E'              from (select x.candidate_value cv from pipeline.layer3_interpretations x where x.entity_type = ''course'' and x.entity_id = pg.course_id and x.status = ''validated''\n'
    || E'                       and x.task_class = ''provider_intake_validation'' and jsonb_typeof(x.candidate_value->''months'') = ''array'' order by x.created_at desc limit 1) l) r5_itk,\n'
    || E'           (select (select (t->>''overall'')::numeric from jsonb_array_elements(l.cv->''tests'') t where t->>''test'' = ''IELTS'' limit 1)\n'
    || E'                   = (select r3.overall_score from catalogue.course_english_requirements r3 join ref.english_tests t3 on t3.id = r3.english_test_id where r3.course_id = pg.course_id and t3.code = ''IELTS'' and coalesce(r3.status, ''active'') = ''active'' limit 1)\n'
    || E'              from (select x.candidate_value cv from pipeline.layer3_interpretations x where x.entity_type = ''course'' and x.entity_id = pg.course_id and x.status = ''validated''\n'
    || E'                       and x.task_class = ''provider_english_validation'' and jsonb_typeof(x.candidate_value->''tests'') = ''array'' order by x.created_at desc limit 1) l) r5_eng,\n'
    || E'           (select abs((l.cv->>''amount'')::numeric - (select f.amount from catalogue.course_fees f where f.course_id = pg.course_id and f.status = ''active'' and f.fee_type = ''provider_current_tuition'' and f.audience = ''international'' order by f.fee_year desc nulls last limit 1))\n'
    || E'                   <= 0.01 * (l.cv->>''amount'')::numeric\n'
    || E'              from (select x.candidate_value cv from pipeline.layer3_interpretations x where x.entity_type = ''course'' and x.entity_id = pg.course_id and x.status = ''validated''\n'
    || E'                       and x.task_class = ''provider_current_tuition_validation'' and (x.candidate_value->>''amount'') ~ ''^[0-9]+(\\.[0-9]+)?$'' order by x.created_at desc limit 1) l) r5_fee\n'
    || E'      from pipeline');
  d := replace(d, '''intakes'' = any (r.af)', '((''intakes'' = any (r.af) and r.adm) or coalesce(r.r5_itk, false))');
  d := replace(d, '''english'' = any (r.af)', '((''english'' = any (r.af) and r.adm) or coalesce(r.r5_eng, false))');
  d := replace(d, '''fee'' = any (r.af)', '((''fee'' = any (r.af) and r.adm) or coalesce(r.r5_fee, false))');
  d := replace(d, '''delivery'' = any (r.af)', '(''delivery'' = any (r.af) and r.adm)');
  execute d;
end $p$;
