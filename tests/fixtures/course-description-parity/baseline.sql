-- Guards: Platform Admin direction 6 Nov 2026 08:12 (course descriptions: safe parallel planning and independent validation).
-- Regression base for the course-description validator: what the LIVE security.course_description_check_v1 (md5 ff3d6dd7b0f88c85b1fdff6c8a8cd86b,
-- captured 6 Nov 2026 08:29 AEDT) decides today for representative held cases. Any change to the validator, its settings or the shared pdesc
-- helpers that changes one of these outcomes fails here; a deliberate change updates the expected rule with the decision that authorises it.
-- Facts this baseline pins (they shape the implementation plan):
--   * the check reports only the FIRST rule broken, in this order: not_stated, sentence_count, then per sentence quote_not_on_page,
--     unsupported_marketing, unsupported_claim, incomplete_sentence, unsupported_sentence; then length; then duplicate_other_course;
--   * a length hold has passed every per-sentence check; a sentence_count hold has had none of them run;
--   * pdesc.claim_words (shared with provider descriptions) holds ordinary course words such as "students", "staff" and "employment"
--     when the sentence's own quote does not contain the same word;
--   * nothing is cut: a long or many-sentence reading is held whole.
-- Fixture rows are invented (fresh ids); the sentence shapes follow held readings in production (field_enrich_items, field description,
-- 3-5 Nov 2026). No user data.
\set ON_ERROR_STOP 1
-- :after = 1 runs the same cases against the database AFTER migration 20261106500000 (run.sh does both): every outcome must be identical.
\if :{?after}
\else
\set after 0
\endif
set search_path to "$user", public, extensions;

insert into pim.entity_registry(id, stable_key) values
  ('00000000-0000-4000-8000-0000000000a1', 'g-fx-provider-a'), ('00000000-0000-4000-8000-0000000000b1', 'g-fx-provider-b'),
  ('00000000-0000-4000-8000-000000000c01', 'g-fx-course-1'), ('00000000-0000-4000-8000-000000000c02', 'g-fx-course-2'),
  ('00000000-0000-4000-8000-000000000c03', 'g-fx-course-3');
insert into catalogue.providers(id, stable_key, canonical_name, country_id) values
  ('00000000-0000-4000-8000-0000000000a1', 'g-fx-provider-a', 'Fixture University A', (select id from ref.countries where iso_alpha2 = 'AU')),
  ('00000000-0000-4000-8000-0000000000b1', 'g-fx-provider-b', 'Fixture University B', (select id from ref.countries where iso_alpha2 = 'NZ'));
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, description) values
  ('00000000-0000-4000-8000-000000000c01', 'g-fx-course-1', '00000000-0000-4000-8000-0000000000a1', 'Bachelor of Environmental Science', null),
  ('00000000-0000-4000-8000-000000000c02', 'g-fx-course-2', '00000000-0000-4000-8000-0000000000a1', 'Bachelor of Marine Science',
   'This degree develops practical skills in field sampling, laboratory analysis and data interpretation across coastal and ocean systems. You complete a research project in your final year with an industry or government partner.'),
  ('00000000-0000-4000-8000-000000000c03', 'g-fx-course-3', '00000000-0000-4000-8000-0000000000b1', 'Master of Data Science', null);

create temporary table g_case(n int primary key, label text, course uuid, expect text, result jsonb);

-- s(text, quote): one sentence with its quote, marked on the page (the worker sets on_page after matching the quote to the page)
create function pg_temp.s(t text, q text, on_page boolean default true) returns jsonb language sql as
  $$ select jsonb_build_object('text', t, 'quote', q, 'on_page', on_page) $$;
create function pg_temp.r(variadic xs jsonb[]) returns jsonb language sql as
  $$ select jsonb_build_object('about_course', true, 'sentences', to_jsonb(xs)) $$;

insert into g_case(n, label, course, expect, result) values
(1, 'passes: three supported sentences, 80-700 characters', '00000000-0000-4000-8000-000000000c01', 'ok',
 pg_temp.r(pg_temp.s('This degree examines how natural systems work and how human activity changes them.', 'This degree examines how natural systems work and how human activity changes them.'),
           pg_temp.s('You study ecology, geology, chemistry and environmental policy.', 'In this course you will study ecology, geology, chemistry and environmental policy.'),
           pg_temp.s('Fieldwork units take you to rivers, forests and coastal sites.', 'Fieldwork units take you to rivers, forests and coastal sites across the state.'))),
(2, 'not stated: the page is not about the course', '00000000-0000-4000-8000-000000000c01', 'not_stated',
 jsonb_build_object('about_course', false, 'sentences', '[]'::jsonb)),
(3, 'too many sentences: 5 against max 4 (held whole, never cut)', '00000000-0000-4000-8000-000000000c01', 'sentence_count',
 pg_temp.r(pg_temp.s('This degree examines how natural systems work.', 'This degree examines how natural systems work.'),
           pg_temp.s('You study ecology and geology.', 'You study ecology and geology.'),
           pg_temp.s('You also study chemistry.', 'You also study chemistry.'),
           pg_temp.s('Policy units cover environmental law.', 'Policy units cover environmental law.'),
           pg_temp.s('Fieldwork takes you to coastal sites.', 'Fieldwork takes you to coastal sites.'))),
(4, 'too many sentences AND a claim word: sentence_count is reported, the claim is never checked', '00000000-0000-4000-8000-000000000c01', 'sentence_count',
 pg_temp.r(pg_temp.s('Students examine how natural systems work.', 'This degree examines how natural systems work.'),
           pg_temp.s('You study ecology and geology.', 'You study ecology and geology.'),
           pg_temp.s('You also study chemistry.', 'You also study chemistry.'),
           pg_temp.s('Policy units cover environmental law.', 'Policy units cover environmental law.'),
           pg_temp.s('Fieldwork takes you to coastal sites.', 'Fieldwork takes you to coastal sites.'))),
(5, 'too long: 4 supported sentences over 700 characters (held whole, never cut)', '00000000-0000-4000-8000-000000000c01', 'length',
 pg_temp.r(pg_temp.s('This degree examines how natural systems work and how human activity changes them over time, drawing on the physical, chemical and biological sciences to explain the processes that shape landscapes, waterways, soils and the atmosphere in both regional and urban settings.',
                     'This degree examines how natural systems work and how human activity changes them over time, drawing on the physical, chemical and biological sciences to explain the processes that shape landscapes, waterways, soils and the atmosphere in both regional and urban settings.'),
           pg_temp.s('You study ecology, geology, chemistry, hydrology and environmental policy, and you learn to collect, analyse and interpret field and laboratory data using current methods and software used by government agencies and consultancies.',
                     'You study ecology, geology, chemistry, hydrology and environmental policy, and you learn to collect, analyse and interpret field and laboratory data using current methods and software used by government agencies and consultancies.'),
           pg_temp.s('Fieldwork units take you to rivers, forests, wetlands and coastal sites, where you design sampling programs and report on the condition of the environment.',
                     'Fieldwork units take you to rivers, forests, wetlands and coastal sites, where you design sampling programs and report on the condition of the environment.'),
           pg_temp.s('In your final year you complete a research project with an industry, community or government partner.',
                     'In your final year you complete a research project with an industry, community or government partner.'))),
(6, 'too long AND a claim word: the claim is reported first (length is checked last)', '00000000-0000-4000-8000-000000000c01', 'unsupported_claim',
 pg_temp.r(pg_temp.s('This degree examines how natural systems work and how human activity changes them over time, drawing on the physical, chemical and biological sciences to explain the processes that shape landscapes, waterways, soils and the atmosphere in both regional and urban settings.',
                     'This degree examines how natural systems work and how human activity changes them over time, drawing on the physical, chemical and biological sciences to explain the processes that shape landscapes, waterways, soils and the atmosphere in both regional and urban settings.'),
           pg_temp.s('Students study ecology, geology, chemistry, hydrology and environmental policy, and learn to collect, analyse and interpret field and laboratory data using current methods and software used by government agencies and consultancies.',
                     'You study ecology, geology, chemistry, hydrology and environmental policy, and you learn to collect, analyse and interpret field and laboratory data using current methods and software used by government agencies and consultancies.'),
           pg_temp.s('Fieldwork units take you to rivers, forests, wetlands and coastal sites, where you design sampling programs and report on the condition of the environment.',
                     'Fieldwork units take you to rivers, forests, wetlands and coastal sites, where you design sampling programs and report on the condition of the environment.'),
           pg_temp.s('In your final year you complete a research project with an industry, community or government partner.',
                     'In your final year you complete a research project with an industry, community or government partner.'))),
(7, 'unsupported claim: an ordinary word ("students") that the quote phrases as "you"', '00000000-0000-4000-8000-000000000c03', 'unsupported_claim',
 pg_temp.r(pg_temp.s('Students learn to build, test and explain statistical and machine learning models.', 'You will learn to build, test and explain statistical and machine learning models.'))),
(8, 'claim word inside its own quote: passes', '00000000-0000-4000-8000-000000000c03', 'ok',
 pg_temp.r(pg_temp.s('Students learn to build, test and explain statistical and machine learning models.', 'Students learn to build, test and explain statistical and machine learning models.'))),
(9, 'unsupported claim: an outcome word ("employment") not in the quote', '00000000-0000-4000-8000-000000000c03', 'unsupported_claim',
 pg_temp.r(pg_temp.s('The course prepares you for employment in analytics and data engineering roles.', 'The course prepares you for analytics and data engineering roles in industry.'))),
(10, 'unsupported claim: accreditation not in the quote', '00000000-0000-4000-8000-000000000c03', 'unsupported_claim',
 pg_temp.r(pg_temp.s('The degree is accredited and covers statistics, programming and data ethics.', 'The degree covers statistics, programming and data ethics.'))),
(11, 'marketing word not in the quote', '00000000-0000-4000-8000-000000000c03', 'unsupported_marketing',
 pg_temp.r(pg_temp.s('This leading course covers statistics, programming and data ethics.', 'This course covers statistics, programming and data ethics.'))),
(12, 'quote not on the page', '00000000-0000-4000-8000-000000000c03', 'quote_not_on_page',
 pg_temp.r(pg_temp.s('This course covers statistics, programming and data ethics.', 'This course covers statistics, programming and data ethics.', false))),
(13, 'incomplete sentence (a fragment, never completed)', '00000000-0000-4000-8000-000000000c03', 'incomplete_sentence',
 pg_temp.r(pg_temp.s('This course covers statistics, programming, data ethics and', 'This course covers statistics, programming, data ethics and'))),
(14, 'sentence not supported by its quote', '00000000-0000-4000-8000-000000000c03', 'unsupported_sentence',
 pg_temp.r(pg_temp.s('Graduates design pipelines, visualise findings and advise organisations on governance.', 'This course covers statistics, programming and data ethics.'))),
(15, 'too short (under 80 characters)', '00000000-0000-4000-8000-000000000c03', 'length',
 pg_temp.r(pg_temp.s('This course covers statistics.', 'This course covers statistics.'))),
(16, 'the same words as another course of the provider (boilerplate)', '00000000-0000-4000-8000-000000000c01', 'duplicate_other_course',
 pg_temp.r(pg_temp.s('This degree develops practical skills in field sampling, laboratory analysis and data interpretation across coastal and ocean systems.', 'This degree develops practical skills in field sampling, laboratory analysis and data interpretation across coastal and ocean systems.'),
           pg_temp.s('You complete a research project in your final year with an industry or government partner.', 'You complete a research project in your final year with an industry or government partner.')));

update g_case set result = security.course_description_check_v1(course, result) where true;

do $$ declare c record; v_bad int := 0; begin
  for c in select * from g_case order by n loop
    raise notice 'case % [%] expect % got % (sentences %, chars %): %', c.n, case when c.result->>'rule' = c.expect then 'pass' else 'FAIL' end, c.expect, c.result->>'rule',
      c.result->'checks'->>'sentences', c.result->'checks'->>'chars', c.label;
    if c.result->>'rule' is distinct from c.expect then v_bad := v_bad + 1; end if;
    if (c.result->>'rule' = 'ok') is distinct from coalesce((c.result->>'ok')::boolean, false) then raise exception 'case %: ok flag and rule disagree', c.n; end if;
    if c.result->>'rule' <> 'ok' and c.result ? 'text' then raise exception 'case %: a held reading returned text (nothing is cut or admitted)', c.n; end if;
  end loop;
  if v_bad > 0 then raise exception '% baseline case(s) changed outcome', v_bad; end if;
end $$;

-- Trust: with review_first = 100000 (D5 hold) and no decided items, no provider is trusted.
do $$ begin
  if security.course_description_trusted_v1('00000000-0000-4000-8000-0000000000a1') then raise exception 'a provider is trusted under the D5 hold'; end if;
  raise notice 'trust [pass]: no provider trusted while enrich.course_description_review_first = %', security.pipeline_num_v1('enrich.course_description_review_first', 5);
end $$;

\if :after
-- After the migration: the check is a wrapper of check_with_v1, which reads the course lists, and the lists equal the provider lists (D2, D5).
do $$ begin
  if position('course_description_check_with_v1' in pg_get_functiondef('security.course_description_check_v1(uuid,jsonb)'::regprocedure)) = 0 then raise exception 'check_v1 is not the wrapper'; end if;
  if position('enrich.course_description_claim_words' in pg_get_functiondef('security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)'::regprocedure)) = 0 then raise exception 'the course claim list is not read'; end if;
  if position('enrich.course_description_marketing_words' in pg_get_functiondef('security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)'::regprocedure)) = 0 then raise exception 'the course marketing list is not read'; end if;
  raise notice 'claim list [pass]: the check reads the course lists, seeded identical to the provider lists';
end $$;
\else
-- The shared claim list is the one the check reads today (PR #877 adds pdesc.evidence_claim_words for providers only).
do $$ begin
  if position('pdesc.claim_words' in pg_get_functiondef('security.course_description_check_v1(uuid,jsonb)'::regprocedure)) = 0 then raise exception 'the check no longer reads pdesc.claim_words'; end if;
  if position('enrich.course_description_claim_words' in pg_get_functiondef('security.course_description_check_v1(uuid,jsonb)'::regprocedure)) > 0 then raise exception 'the course claim list already exists: re-baseline'; end if;
  raise notice 'claim list [pass]: course_description_check_v1 reads pipeline / pdesc.claim_words (shared with provider descriptions)';
end $$;
\endif
