-- E16 fixtures (CF-247 E16-1/E16-2, Platform Admin 2 Nov 2026 07:21): every documented failure class of course page binding, the allowed
-- exceptions, the award-link lane, Layer 4 routing without duplicates, the AI reader's page choice and the projection tie-break.
-- Each case raises a notice "PASS ..." or stops with an error. The courses and pages are modelled on the E16 cohort, SS-007 (§17-§18) and
-- E14 (EIT combined pages); no live data.
\set ON_ERROR_STOP 1
create function pg_temp.ok(p boolean, p_what text) returns void language plpgsql as $f$
begin if p is not true then raise exception 'FAIL %', p_what; end if; end $f$;
create function pg_temp.u(p text) returns uuid language sql immutable as $f$ select md5(p)::uuid $f$;
-- a course: provider key, code, title, level
create function pg_temp.course(p_key text, p_prov text, p_code text, p_title text, p_level text) returns uuid language sql as $f$
  insert into catalogue.courses(id, provider_id, canonical_title, course_code, study_level_id)
  values (pg_temp.u(p_key), pg_temp.u(p_prov), p_title, p_code, (select id from ref.study_levels where code = p_level)) returning id $f$;
-- a binding that has been read, with the page's title (the reader's candidates)
create function pg_temp.read_page(p_key text, p_prov text, p_url text, p_title text) returns void language sql as $f$
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, read_status, identity_basis, evidence_id, candidates)
  values (pg_temp.u(p_key), pg_temp.u(p_prov), p_url, 'cricos_search', 'bound', 'read', 'cricos_code', pg_temp.u('ev ' || p_url),
          jsonb_build_object('page_title', p_title, 'final_url', p_url)) $f$;
create function pg_temp.page(p_key text) returns pipeline.coverage_course_pages language sql as $f$ select * from pipeline.coverage_course_pages where course_id = pg_temp.u(p_key) $f$;
create function pg_temp.l4(p_key text) returns bigint language sql as $f$
  select count(*) from pipeline.layer4_review_items where entity_id = pg_temp.u(p_key) and field_code = 'official_course_url' and status = 'pending' $f$;
create function pg_temp.rule(p_key text, p_url text) returns text language sql as $f$
  select signals->>'rule' from pipeline.page_rejections where course_id = pg_temp.u(p_key) and url = p_url $f$;

-- providers, sources and stored page copies --------------------------------------------------------------------------------------------
insert into catalogue.providers(id, canonical_name, website) values
  (pg_temp.u('rmit'), 'RMIT University', 'https://www.rmit.edu.au'), (pg_temp.u('latrobe'), 'La Trobe University', 'https://www.latrobe.edu.au'),
  (pg_temp.u('lennox'), 'Lennox Institute', 'https://lennoxcollege.edu.au'), (pg_temp.u('griffith'), 'Griffith University', 'https://www.griffith.edu.au'),
  (pg_temp.u('unimelb'), 'The University of Melbourne', 'https://www.unimelb.edu.au'), (pg_temp.u('eit'), 'Eastern Institute of Technology', 'https://www.eit.ac.nz'),
  (pg_temp.u('school'), 'Bayside Secondary College', 'https://www.bayside.vic.edu.au'), (pg_temp.u('elicos'), 'Harbour English', 'https://www.harbourenglish.edu.au'),
  (pg_temp.u('other'), 'Other University', 'https://www.otheruni.edu.au'), (pg_temp.u('usyd'), 'The University of Sydney', 'https://www.sydney.edu.au'),
  (pg_temp.u('nurse'), 'Coastal Nursing Institute', 'https://www.coastal.edu.au');
insert into pipeline.sources(id, source_type, provider_id, label) values (pg_temp.u('sweep'), 'provider_course_page_sweep', null, 'course pages (coverage sweep)'),
  (pg_temp.u('reviewer'), 'layer4_human_review', null, 'reviewer'), (pg_temp.u('manual'), 'manual_entry', null, 'manual');
insert into search.enrichment_source_gates values ('courses', 'official_course_url', pg_temp.u('sweep'), 'approved'), ('courses', 'official_course_url', pg_temp.u('reviewer'), 'approved'),
  ('courses', 'official_course_url', pg_temp.u('manual'), 'approved');
insert into pipeline.evidence_artifacts(id, storage_path, source_url)
select pg_temp.u('ev ' || u), 'snap/' || md5(u) || '.html.gz', u from unnest(array[
  'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-advertising-mc249',
  'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/graduate-diplomas/graduate-diploma-of-advertising-gd197',
  'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-media-mc188',
  'https://www.griffith.edu.au/study/degrees/master-of-professional-accounting-5683',
  'https://handbook.latrobe.edu.au/courses/2024/bg005', 'https://handbook.unimelb.edu.au/2026/courses/mc-tesol', 'https://handbook.unimelb.edu.au/2026/courses/gc-tesol',
  'https://www.eit.ac.nz/programmes/master-of-information-technology/', 'https://www.sydney.edu.au/courses/bachelor-of-pharmacy-honours-and-master-of-pharmacy-practice.html',
  'https://www.coastal.edu.au/courses/bachelor-of-nursing']) u;

-- courses
select pg_temp.course('rmit gd adv', 'rmit', '103222G', 'Graduate Diploma of Advertising', 'graduate_diploma'),
       pg_temp.course('rmit m adv', 'rmit', '083688M', 'Master of Advertising', 'masters_coursework'),
       pg_temp.course('rmit gd media', 'rmit', '103217D', 'Graduate Diploma in Media', 'graduate_diploma'),
       pg_temp.course('rmit m media', 'rmit', '086111K', 'Master of Media', 'masters_coursework'),
       pg_temp.course('rmit gd ex', 'rmit', '103221H', 'Graduate Diploma of Communication', 'graduate_diploma'),
       pg_temp.course('rmit m comm', 'rmit', '083694B', 'Master of Communication', 'masters_coursework'),
       pg_temp.course('rmit gc hand', 'rmit', '103226C', 'Graduate Certificate in Energy Efficient and Sustainable Building', 'graduate_certificate'),
       pg_temp.course('rmit m build', 'rmit', '083700M', 'Master of Energy Efficient and Sustainable Building', 'masters_coursework'),
       pg_temp.course('griffith gc acc', 'griffith', '107421A', 'Graduate Certificate in Professional Accounting', 'graduate_certificate'),
       pg_temp.course('griffith m acc', 'griffith', '072381B', 'Master of Professional Accounting', 'masters_coursework'),
       pg_temp.course('latrobe gd fin', 'latrobe', '107089H', 'Graduate Diploma in Financial Analysis', 'graduate_diploma'),
       pg_temp.course('latrobe gd old', 'latrobe', '080518G', 'Graduate Diploma in International Relations', 'graduate_diploma'),
       pg_temp.course('lennox gd', 'lennox', '108224J', 'Graduate Diploma of Management (Learning)', 'graduate_diploma'),
       pg_temp.course('unimelb gc tesol', 'unimelb', '095993A', 'Graduate Certificate in TESOL', 'graduate_certificate'),
       pg_temp.course('unimelb m tesol', 'unimelb', '095994M', 'Master of TESOL', 'masters_coursework'),
       pg_temp.course('eit mit 240', 'eit', 'EIT-MIT240', 'Master of Information Technology (240 credits)', 'masters_coursework'),
       pg_temp.course('eit mit 180', 'eit', 'EIT-MIT180', 'Master of Information Technology (180 credits)', 'masters_coursework'),
       pg_temp.course('eit pgcert', 'eit', 'EIT-PGCIT', 'Postgraduate Certificate in Information Technology', 'graduate_certificate'),
       pg_temp.course('school y10', 'school', '0100001', 'Year 10', 'senior_secondary_certificate'),
       pg_temp.course('school y11', 'school', '0100002', 'Year 11', 'senior_secondary_certificate'),
       pg_temp.course('school y12', 'school', '0100003', 'Year 12', 'senior_secondary_certificate'),
       pg_temp.course('elicos int', 'elicos', '0200001', 'General English (Intermediate)', 'non_aqf_award'),
       pg_temp.course('elicos adv', 'elicos', '0200002', 'General English (Advanced)', 'non_aqf_award'),
       pg_temp.course('elicos beg', 'elicos', '0200003', 'General English (Beginner)', 'non_aqf_award'),
       pg_temp.course('usyd pharm', 'usyd', '000723J', 'Bachelor of Pharmacy', 'bachelor'),
       pg_temp.course('nurse b', 'nurse', '0300001', 'Bachelor of Nursing', 'bachelor'),
       pg_temp.course('nurse ge', 'nurse', '0300002', 'Bachelor of Nursing (Graduate Entry)', 'bachelor'),
       pg_temp.course('proj multi', 'rmit', '0999001', 'Master of Media', 'masters_coursework'),
       pg_temp.course('proj sib', 'rmit', '0999002', 'Graduate Diploma of Advertising', 'graduate_diploma'),
       pg_temp.course('proj one', 'rmit', '0999003', 'Master of Advertising', 'masters_coursework'),
       pg_temp.course('proj prim', 'rmit', '0999004', 'Graduate Diploma in Media', 'graduate_diploma');
insert into catalogue.course_regulatory_observations(course_id, vet_national_code) values (pg_temp.u('lennox gd'), 'BSB80120');

-- pages read for their own courses (the parent pages' titles are what a sibling binding is judged by) and bindings made before E16 (an EIT combined
-- page bound to the 240 point master and the certificate): written with the guard off, as they are live today
alter table pipeline.coverage_course_pages disable trigger coverage_page_refused_host;
select pg_temp.read_page('rmit m adv', 'rmit', 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-advertising-mc249', 'Master of Advertising - RMIT University'),
       pg_temp.read_page('rmit m media', 'rmit', 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-media-mc188', 'Master of Media - RMIT University'),
       pg_temp.read_page('griffith m acc', 'griffith', 'https://www.griffith.edu.au/study/degrees/master-of-professional-accounting-5683', 'Master of Professional Accounting | Griffith University'),
       pg_temp.read_page('unimelb m tesol', 'unimelb', 'https://handbook.unimelb.edu.au/2026/courses/mc-tesol', 'Master of TESOL (MC-TESOL) - The University of Melbourne Handbook'),
       pg_temp.read_page('latrobe gd fin', 'latrobe', 'https://handbook.latrobe.edu.au/courses/2024/bg005', 'Graduate Diploma in Financial Analysis - Melbourne (Bundoora) (BG005) | La Trobe Handbook'),
       pg_temp.read_page('eit mit 240', 'eit', 'https://www.eit.ac.nz/programmes/master-of-information-technology/', 'Master of Information Technology | EIT'),
       pg_temp.read_page('eit pgcert', 'eit', 'https://www.eit.ac.nz/programmes/master-of-information-technology/', 'Master of Information Technology | EIT'),
       pg_temp.read_page('school y10', 'school', 'https://www.bayside.vic.edu.au/study-with-us-overseas', 'Study with us from overseas'),
       pg_temp.read_page('school y11', 'school', 'https://www.bayside.vic.edu.au/study-with-us-overseas', 'Study with us from overseas'),
       pg_temp.read_page('elicos int', 'elicos', 'https://www.harbourenglish.edu.au/general-english', 'General English'),
       pg_temp.read_page('elicos adv', 'elicos', 'https://www.harbourenglish.edu.au/general-english', 'General English');
alter table pipeline.coverage_course_pages enable trigger coverage_page_refused_host;
insert into catalogue.course_links(course_id, url, source_id, last_verified_at) values
  (pg_temp.u('latrobe gd fin'), 'https://handbook.latrobe.edu.au/courses/2024/bg005', pg_temp.u('sweep'), now() - interval '20 days');

do $$
declare r pipeline.coverage_course_pages; v jsonb; n0 bigint;
begin
  -- 1. sibling award: a Graduate Diploma bound to its Master's page (RMIT 103222G -> master-of-advertising-mc249), any lane ------------------
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status)
  values (pg_temp.u('rmit gd adv'), pg_temp.u('rmit'), 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-advertising-mc249', 'title_search', 'bound');
  r := pg_temp.page('rmit gd adv');
  perform pg_temp.ok(r.status = 'mismatch' and r.read_status = 'identity_refused' and r.identity_basis is null and r.next_read_at is null, 'sibling award refused at bind');
  perform pg_temp.ok(pg_temp.rule('rmit gd adv', r.url) = 'level', 'rejection records the level rule');
  perform pg_temp.ok(pg_temp.l4('rmit gd adv') = 1, 'one Layer 4 course link item');
  perform pg_temp.ok((select escalation_reason from pipeline.layer4_review_items where entity_id = pg_temp.u('rmit gd adv')) like 'The page found automatically was not linked: the page is for another qualification level (M), not this course''s (GD)%', 'plain reason');
  perform pg_temp.ok((select proposed_value->>'course_url' from pipeline.layer4_review_items where entity_id = pg_temp.u('rmit gd adv')) = r.url, 'existing course-link shape (proposed course_url)');
  -- the same through a re-bind (update of the address), Griffith 107421A -> master-of-professional-accounting-5683
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status) values (pg_temp.u('griffith gc acc'), pg_temp.u('griffith'), 'https://www.griffith.edu.au/study/degrees/graduate-certificate-in-professional-accounting-3001', 'title_search', 'bound');
  perform pg_temp.ok((pg_temp.page('griffith gc acc')).status = 'bound', 'own-level page stays bound (unproven, not refused)');
  update pipeline.coverage_course_pages set url = 'https://www.griffith.edu.au/study/degrees/master-of-professional-accounting-5683' where course_id = pg_temp.u('griffith gc acc');
  perform pg_temp.ok((pg_temp.page('griffith gc acc')).status = 'mismatch' and pg_temp.rule('griffith gc acc', 'https://www.griffith.edu.au/study/degrees/master-of-professional-accounting-5683') = 'level', 'sibling award refused at re-bind');
  -- and at first read, when the reader's identity proof arrives (Melbourne 095993A -> /mc-tesol)
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, read_status) values (pg_temp.u('unimelb gc tesol'), pg_temp.u('unimelb'), 'https://handbook.unimelb.edu.au/2026/courses/mc-tesol', 'cricos_search', 'ambiguous', null);
  perform pg_temp.ok((pg_temp.page('unimelb gc tesol')).status = 'mismatch', 'Melbourne mc- handbook code read as a Master''s page');
  raise notice 'PASS sibling award (Graduate Certificate/Diploma -> Master)';

  -- 2. older handbook year (La Trobe 107089H: 2024/bg005 held, 2021/LMFAN offered) and a year past the allowed age -----------------------
  update pipeline.coverage_course_pages set url = 'https://handbook.latrobe.edu.au/courses/2021/LMFAN', read_status = null, candidates = null where course_id = pg_temp.u('latrobe gd fin');
  r := pg_temp.page('latrobe gd fin');
  perform pg_temp.ok(r.status = 'mismatch' and pg_temp.rule('latrobe gd fin', r.url) = 'older_year', 'older handbook year refused');
  perform pg_temp.ok(security.course_page_check_v1(pg_temp.u('latrobe gd old'), 'https://handbook.latrobe.edu.au/courses/2021/AMIRL')->>'rule' = 'old_year', 'handbook older than the allowed years refused');
  perform pg_temp.ok(security.course_page_check_v1(pg_temp.u('latrobe gd fin'), 'https://handbook.latrobe.edu.au/courses/2024/bg005')->>'verdict' <> 'refuse', 'the held 2024 page is not refused');
  raise notice 'PASS older handbook year';

  -- 3. fee, application, ESOS and course-list pages (SS-007 classes A-C) -----------------------------------------------------------------
  foreach v in array array['"https://www.rmit.edu.au/study-with-us/international-students/fees"', '"https://www.rmit.edu.au/study-with-us/how-to-apply"',
                           '"https://www.rmit.edu.au/study-with-us/esos"', '"https://www.rmit.edu.au/study-with-us/courses/"']::jsonb[] loop
    perform pg_temp.ok(security.course_page_check_v1(pg_temp.u('rmit gd media'), v #>> '{}')->>'rule' = 'shared_page', 'shared page refused: ' || (v #>> '{}'));
  end loop;
  raise notice 'PASS fee, application and course-list pages';

  -- 4. a school's international page for its year-level courses (SS-007 class D): bound to two other year levels -----------------------
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status) values (pg_temp.u('school y12'), pg_temp.u('school'), 'https://www.bayside.vic.edu.au/study-with-us-overseas', 'title_search', 'bound');
  perform pg_temp.ok((pg_temp.page('school y12')).status = 'mismatch' and pg_temp.rule('school y12', 'https://www.bayside.vic.edu.au/study-with-us-overseas') = 'shared_page', 'school international page refused');
  perform pg_temp.ok(security.course_page_check_v1(pg_temp.u('school y12'), 'https://www.bayside.vic.edu.au/international-students/')->>'rule' = 'shared_page', 'school international page by address');
  raise notice 'PASS school international page';

  -- 5. one page for many ELICOS levels (SS-007 class E) -----------------------------------------------------------------------------------
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status) values (pg_temp.u('elicos beg'), pg_temp.u('elicos'), 'https://www.harbourenglish.edu.au/general-english', 'cricos_search', 'bound');
  perform pg_temp.ok((pg_temp.page('elicos beg')).status = 'mismatch' and pg_temp.rule('elicos beg', 'https://www.harbourenglish.edu.au/general-english') = 'shared_page', 'ELICOS levels page refused');
  raise notice 'PASS one page for many ELICOS levels';

  -- 6. EIT combined page (E14): the 180 point master on the page of the 240 point master and the certificate ------------------------------
  v := security.course_page_check_v1(pg_temp.u('eit mit 180'), 'https://www.eit.ac.nz/programmes/master-of-information-technology/');
  perform pg_temp.ok(v->>'rule' = 'shared_page' and (v->'checks'->>'other_titles_on_page')::int = 2, 'EIT combined page refused: ' || v::text);
  raise notice 'PASS EIT combined page';

  -- 7. genuine shared-page exception: approved, and the page names this course's own section ------------------------------------------
  update pipeline.platform_toolset_settings set value = jsonb_build_array(pg_temp.u('eit')::text || '|shared_page|/programmes/master-of-information-technology/')
   where key = 'binding.identity_exceptions';
  perform pg_temp.ok(security.course_page_check_v1(pg_temp.u('eit mit 180'), 'https://www.eit.ac.nz/programmes/master-of-information-technology/')->>'rule' = 'shared_page', 'an approved page that does not name the course is still refused');
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status)
  values (pg_temp.u('eit mit 180'), pg_temp.u('eit'), 'https://www.eit.ac.nz/programmes/master-of-information-technology/#master-of-information-technology-180-credits', 'title_search', 'bound');
  perform pg_temp.ok((pg_temp.page('eit mit 180')).status = 'bound', 'approved shared page with the course''s own section stays bound');
  perform pg_temp.ok(security.course_page_check_v1(pg_temp.u('eit mit 180'), 'https://www.eit.ac.nz/programmes/master-of-information-technology/#master-of-information-technology-180-credits')->>'rule' = 'exception_shared_page', 'exception rule named');
  update pipeline.platform_toolset_settings set value = '[]' where key = 'binding.identity_exceptions';
  raise notice 'PASS genuine shared-page exception (allowed)';

  -- 8. the Lennox false positive: the slug says graduate-certificate but BSB80120 is this Graduate Diploma's own code -------------------
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status)
  values (pg_temp.u('lennox gd'), pg_temp.u('lennox'), 'https://lennoxcollege.edu.au/courses/bsb80120-graduate-certificate-in-management-learning/', 'cricos_search', 'bound');
  perform pg_temp.ok((pg_temp.page('lennox gd')).status = 'bound', 'Lennox stays bound');
  perform pg_temp.ok(security.course_page_check_v1(pg_temp.u('lennox gd'), 'https://lennoxcollege.edu.au/courses/bsb80120-graduate-certificate-in-management-learning/')->>'rule' = 'own_code', 'Lennox passes on its own code');
  raise notice 'PASS Lennox false positive (allowed)';

  -- 9. a domain-only or similar-title match ------------------------------------------------------------------------------------------
  perform pg_temp.ok(security.course_page_check_v1(pg_temp.u('griffith gc acc'), 'https://experts.griffith.edu.au/9306-richard-copp/teaching')->>'rule' = 'name', 'staff page on the provider domain refused');
  perform pg_temp.ok(security.course_page_check_v1(pg_temp.u('nurse b'), 'https://www.coastal.edu.au/courses/bachelor-of-nursing-graduate-entry')->>'verdict' = 'refuse', 'similar title of another version refused');
  perform pg_temp.ok(security.course_page_check_v1(pg_temp.u('rmit gd media'), 'https://www.otheruni.edu.au/courses/graduate-diploma-in-media')->>'rule' = 'provider', 'another provider''s website refused');
  perform pg_temp.ok(security.course_page_check_v1(pg_temp.u('nurse b'), 'https://www.coastal.edu.au/courses/bachelor-of-nursing')->>'verdict' = 'unproven', 'own page, not yet read: unproven, not refused');
  raise notice 'PASS domain-only or similar-title match refused';

  -- 10. no duplicate Layer 4 item ---------------------------------------------------------------------------------------------------------
  n0 := (select count(*) from pipeline.layer4_review_items);
  update pipeline.coverage_course_pages set url = 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-media-mc188', status = 'bound'
   where course_id = pg_temp.u('rmit gd adv');
  perform pg_temp.ok((pg_temp.page('rmit gd adv')).status = 'mismatch' and pg_temp.l4('rmit gd adv') = 1, 'a second refusal keeps the one pending item');
  perform pg_temp.ok((select count(*) from pipeline.page_rejections where course_id = pg_temp.u('rmit gd adv')) = 2, 'each refused page is recorded');
  update pipeline.layer4_review_items set status = 'rejected' where entity_id = pg_temp.u('rmit gd adv');
  delete from pipeline.page_rejections where course_id = pg_temp.u('rmit gd adv');
  update pipeline.coverage_course_pages set url = 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-advertising-mc249', status = 'bound'
   where course_id = pg_temp.u('rmit gd adv');
  perform pg_temp.ok(pg_temp.l4('rmit gd adv') = 0, 'a page a person already decided is not raised again (Decision 263)');
  perform pg_temp.ok((select count(*) from pipeline.layer4_review_items) = n0, 'no new item');
  -- a rejected or blocked page is refused by every lane, without another item (USyd 000723J: blocked 8 Oct, still bound)
  insert into pipeline.course_page_blocks values (pg_temp.u('usyd pharm'), 'https://www.sydney.edu.au/courses/bachelor-of-pharmacy-honours-and-master-of-pharmacy-practice.html', 'Rule 6');
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status)
  values (pg_temp.u('usyd pharm'), pg_temp.u('usyd'), 'https://www.sydney.edu.au/courses/bachelor-of-pharmacy-honours-and-master-of-pharmacy-practice.html', 'title_match', 'bound');
  perform pg_temp.ok((pg_temp.page('usyd pharm')).status = 'mismatch' and (pg_temp.page('usyd pharm')).read_status = 'page_refused' and pg_temp.l4('usyd pharm') = 0, 'blocked page refused at bind');
  raise notice 'PASS no duplicate Layer 4 item';

  -- 11. a page set by hand is not checked; the switch turns the check off --------------------------------------------------------------
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status)
  values (pg_temp.u('rmit gd media'), pg_temp.u('rmit'), 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-media-mc188', 'manual', 'bound');
  perform pg_temp.ok((pg_temp.page('rmit gd media')).status = 'bound', 'manual binding kept');
  delete from pipeline.coverage_course_pages where course_id = pg_temp.u('rmit gd media');
  update pipeline.platform_toolset_settings set value = '0' where key = 'binding.identity_check';
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status)
  values (pg_temp.u('rmit gd media'), pg_temp.u('rmit'), 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-media-mc188', 'title_search', 'bound');
  perform pg_temp.ok((pg_temp.page('rmit gd media')).status = 'bound', 'check off: bound as before');
  update pipeline.platform_toolset_settings set value = '1' where key = 'binding.identity_check';
  delete from pipeline.coverage_course_pages where course_id = pg_temp.u('rmit gd media');
  raise notice 'PASS manual binding and the switch';
end $$;

-- 12. the award-link lane (job exit-awards-apply) ------------------------------------------------------------------------------------------
insert into pipeline.uni_adapters values (pg_temp.u('rmit'), true, true, array['exit_awards']), (pg_temp.u('latrobe'), true, true, array['exit_awards']),
  (pg_temp.u('usyd'), true, true, array['exit_awards']);
insert into pipeline.course_exit_awards(child_course_id, parent_course_id, provider_id, exit_years, page_url, evidence_id, printed, set_by, link_type) values
 -- a title match only (Decision 254 nested award): refused
 (pg_temp.u('rmit gd media'), pg_temp.u('rmit m media'), pg_temp.u('rmit'), 1, 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-media-mc188',
  pg_temp.u('ev https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-media-mc188'),
  'Graduate Diploma in Media within Master of Media (title match, 1 years from its registered length)', 'adapter', 'nested_award'),
 -- an exit award read from the parent page, which names the award: allowed (possible genuine shared page)
 (pg_temp.u('rmit gd ex'), pg_temp.u('rmit m comm'), pg_temp.u('rmit'), 1, 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-communication-mc248',
  pg_temp.u('ev https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-advertising-mc249'),
  'Graduate Diploma of Communication is available as an exit award (1 years from its registered length)', 'adapter', 'exit_award'),
 -- recorded by a person, with evidence: allowed
 (pg_temp.u('rmit gc hand'), pg_temp.u('rmit m build'), pg_temp.u('rmit'), 0.5, 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-energy-efficient-and-sustainable-building-mc209',
  pg_temp.u('ev https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-advertising-mc249'), '0.5 years: Graduate Certificate', 'hand', 'exit_award'),
 -- an older handbook year: refused even with an exit award printed
 (pg_temp.u('latrobe gd old'), pg_temp.u('latrobe gd fin'), pg_temp.u('latrobe'), 1, 'https://handbook.latrobe.edu.au/courses/2021/AMIRL',
  pg_temp.u('ev https://handbook.latrobe.edu.au/courses/2024/bg005'), '1 years: Graduate Diploma in International Relations', 'adapter', 'exit_award'),
 -- a blocked page (USyd 000723J, Rule 6 on 8 Oct): never linked again
 (pg_temp.u('usyd pharm'), pg_temp.u('rmit m adv'), pg_temp.u('usyd'), 1, 'https://www.sydney.edu.au/courses/bachelor-of-pharmacy-honours-and-master-of-pharmacy-practice.html',
  pg_temp.u('ev https://www.sydney.edu.au/courses/bachelor-of-pharmacy-honours-and-master-of-pharmacy-practice.html'), '1 years: Bachelor of Pharmacy', 'hand', 'exit_award');
do $$
declare v jsonb; n0 bigint;
begin
  v := security.exit_awards_apply_v2(pg_temp.u('rmit'));
  perform pg_temp.ok((v->>'applied')::int = 2 and (v->>'refused_identity')::int = 1, 'RMIT: two allowed, one refused: ' || v::text);
  perform pg_temp.ok(not exists (select 1 from catalogue.course_links where course_id = pg_temp.u('rmit gd media')), 'title-match award: no link written');
  perform pg_temp.ok(pg_temp.rule('rmit gd media', 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-media-mc188') = 'level'
                     and pg_temp.l4('rmit gd media') = 1, 'title-match award refused with one Layer 4 item');
  perform pg_temp.ok(exists (select 1 from catalogue.course_links where course_id = pg_temp.u('rmit gd ex') and status = 'active'), 'exit award named on the parent page: linked');
  perform pg_temp.ok(security.course_page_check_v1(pg_temp.u('rmit gd ex'), 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-communication-mc248')->>'rule' = 'award_on_parent_page', 'rule named');
  perform pg_temp.ok(exists (select 1 from catalogue.course_links where course_id = pg_temp.u('rmit gc hand') and status = 'active'), 'award recorded by hand: linked');
  -- the next hourly run refuses nothing again and writes no new rows
  n0 := (select count(*) from pipeline.layer4_review_items) + (select count(*) from pipeline.page_rejections);
  v := security.exit_awards_apply_v2(pg_temp.u('rmit'));
  perform pg_temp.ok((select count(*) from pipeline.layer4_review_items) + (select count(*) from pipeline.page_rejections) = n0, 'unchanged failures are not processed again');
  -- an award link already shown (written before E16) is left as it is, not re-verified and not routed (the §4 re-evaluation decides)
  insert into catalogue.course_links(course_id, url, source_id, last_verified_at) values
    (pg_temp.u('unimelb gc tesol'), 'https://handbook.unimelb.edu.au/2026/courses/mc-tesol', pg_temp.u('sweep'), now() - interval '1 day');
  insert into pipeline.uni_adapters values (pg_temp.u('unimelb'), true, true, array['exit_awards']);
  delete from pipeline.page_rejections where course_id = pg_temp.u('unimelb gc tesol');
  update pipeline.layer4_review_items set status = 'rejected' where entity_id = pg_temp.u('unimelb gc tesol');
  insert into pipeline.course_exit_awards(child_course_id, parent_course_id, provider_id, exit_years, page_url, evidence_id, printed, set_by, link_type)
  values (pg_temp.u('unimelb gc tesol'), pg_temp.u('unimelb m tesol'), pg_temp.u('unimelb'), 0.5, 'https://handbook.unimelb.edu.au/2026/courses/mc-tesol',
          pg_temp.u('ev https://handbook.unimelb.edu.au/2026/courses/mc-tesol'), 'Graduate Certificate in TESOL within Master of TESOL (title match)', 'adapter', 'nested_award');
  n0 := (select count(*) from pipeline.layer4_review_items where status = 'pending');
  v := security.exit_awards_apply_v2(pg_temp.u('unimelb'));
  perform pg_temp.ok((v->>'not_proved_left_for_review')::int = 1 and (v->>'applied')::int = 0, 'existing award link left for review: ' || v::text);
  perform pg_temp.ok((select last_verified_at < now() - interval '12 hours' from catalogue.course_links where course_id = pg_temp.u('unimelb gc tesol')), 'not re-verified');
  perform pg_temp.ok((select count(*) from pipeline.layer4_review_items where status = 'pending') = n0, 'not routed');
  -- older year, blocked page, remediation hold
  v := security.exit_awards_apply_v2(pg_temp.u('latrobe'));
  perform pg_temp.ok((v->>'refused_identity')::int = 1 and pg_temp.rule('latrobe gd old', 'https://handbook.latrobe.edu.au/courses/2021/AMIRL') = 'old_year', 'older-year award refused: ' || v::text);
  v := security.exit_awards_apply_v2(pg_temp.u('usyd'));
  perform pg_temp.ok((v->>'refused_identity')::int = 1 and not exists (select 1 from catalogue.course_links where course_id = pg_temp.u('usyd pharm')), 'blocked page never linked: ' || v::text);
  delete from catalogue.course_links where course_id = pg_temp.u('rmit gd ex');
  insert into pipeline.course_remediation_holds values (pg_temp.u('rmit gd ex'), null);
  v := security.exit_awards_apply_v2(pg_temp.u('rmit'));
  perform pg_temp.ok(not exists (select 1 from catalogue.course_links where course_id = pg_temp.u('rmit gd ex')), 'held course not linked again (SS-007 hold)');
  raise notice 'PASS award-link lane: title match refused, programme-specific evidence allowed, holds and blocks kept, no repeat';
end $$;

-- 13. AI enrichment reads only a proved, not refused page ---------------------------------------------------------------------------------
insert into pipeline.admin_jobs(id) values (pg_temp.u('job'));
insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, read_status, identity_basis, evidence_id, candidates) values
  (pg_temp.u('nurse b'), pg_temp.u('nurse'), 'https://www.coastal.edu.au/courses/bachelor-of-nursing', 'title_search', 'bound', 'needs_render', null,
   pg_temp.u('ev https://www.coastal.edu.au/courses/bachelor-of-nursing'), null);
-- a page bound and read before E16 that the check now refuses (a Graduate Diploma on its Master's page), left as it was
alter table pipeline.coverage_course_pages disable trigger coverage_page_refused_host;
insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, read_status, identity_basis, evidence_id, candidates) values
  (pg_temp.u('proj sib'), pg_temp.u('rmit'), 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-advertising-mc249', 'title_search', 'bound', 'read', 'cricos_code',
   pg_temp.u('ev https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-advertising-mc249'), '{"page_title": "Master of Advertising - RMIT University"}');
alter table pipeline.coverage_course_pages enable trigger coverage_page_refused_host;
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field) values
  (pg_temp.u('job'), pg_temp.u('nurse'), pg_temp.u('nurse b'), 'delivery'), (pg_temp.u('job'), pg_temp.u('rmit'), pg_temp.u('proj sib'), 'delivery'),
  (pg_temp.u('job'), pg_temp.u('rmit'), pg_temp.u('rmit m adv'), 'delivery');
insert into ref.countries(id, iso_alpha2) values (pg_temp.u('au'), 'AU');
update catalogue.providers set country_id = pg_temp.u('au');
do $$
begin
  perform security.enrich_fields_slice_v1(pg_temp.u('job'), 10);
  perform pg_temp.ok((select state <> 'ai' and reason = 'no proven course page: the page found is not proved to be this course''s (E16)' from pipeline.field_enrich_items where course_id = pg_temp.u('nurse b')), 'unproven page not read by the AI');
  perform pg_temp.ok((select state <> 'ai' and storage_path is null from pipeline.field_enrich_items where course_id = pg_temp.u('proj sib')), 'page refused by the check not read by the AI');
  perform pg_temp.ok((select state = 'ai' and storage_path like 'snap/%' from pipeline.field_enrich_items where course_id = pg_temp.u('rmit m adv')), 'the course''s own proved page is read');
  raise notice 'PASS AI enrichment skips unproven and refused pages';
end $$;

-- 14. projection tie-break (E16-2) --------------------------------------------------------------------------------------------------------
select pg_temp.course('proj spell', 'rmit', '0999005', 'Master of Design', 'masters_coursework');
insert into search.course_documents(course_id, country_code) select pg_temp.u(k), 'AU' from unnest(array['proj multi', 'proj sib', 'proj one', 'proj prim', 'proj spell']) k;
alter table pipeline.coverage_course_pages disable trigger coverage_page_refused_host;
insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, read_status, identity_basis, evidence_id) values
  (pg_temp.u('proj multi'), pg_temp.u('rmit'), 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-media-mc188', 'cricos_search', 'bound', 'read', 'cricos_code', null);
alter table pipeline.coverage_course_pages enable trigger coverage_page_refused_host;
update catalogue.courses set course_url = 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-media-mc188' where id = pg_temp.u('proj multi');
update catalogue.courses set course_url = 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-advertising-mc249' where id = pg_temp.u('proj sib');
update catalogue.courses set course_url = 'http://rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-design-mc300/' where id = pg_temp.u('proj spell');
alter table pipeline.coverage_course_pages disable trigger coverage_page_refused_host;
insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, read_status, identity_basis, evidence_id) values
  (pg_temp.u('proj spell'), pg_temp.u('rmit'), 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-design-mc300', 'cricos_search', 'bound', 'read', 'cricos_code', null);
alter table pipeline.coverage_course_pages enable trigger coverage_page_refused_host;
insert into catalogue.course_links(course_id, url, source_id, last_verified_at) values
  (pg_temp.u('proj spell'), 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-design-mc300', pg_temp.u('sweep'), now() - interval '30 days'),
  (pg_temp.u('proj spell'), 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/graduate-diplomas/graduate-diploma-of-design-gd300', pg_temp.u('sweep'), now());
insert into catalogue.course_links(course_id, url, source_id, last_verified_at, is_primary) values
  -- several links, none primary, course_url passes: course_url shown, not the more recent one
  (pg_temp.u('proj multi'), 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-media-mc188', pg_temp.u('sweep'), now() - interval '30 days', false),
  (pg_temp.u('proj multi'), 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/graduate-diplomas/graduate-diploma-in-media-gd180', pg_temp.u('sweep'), now(), false),
  -- several links, none primary, course_url is a sibling page: none shown
  (pg_temp.u('proj sib'), 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-advertising-mc249', pg_temp.u('sweep'), now(), false),
  (pg_temp.u('proj sib'), 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/graduate-diplomas/graduate-diploma-of-advertising-gd197', pg_temp.u('sweep'), now() - interval '30 days', false),
  -- one link: shown as before
  (pg_temp.u('proj one'), 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-advertising-mc249', pg_temp.u('sweep'), now(), false),
  -- a primary link: shown as before
  (pg_temp.u('proj prim'), 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/graduate-diplomas/graduate-diploma-in-media-gd180', pg_temp.u('reviewer'), now() - interval '30 days', true),
  (pg_temp.u('proj prim'), 'https://www.rmit.edu.au/study-with-us/levels-of-study/postgraduate-study/masters-by-coursework/master-of-media-mc188', pg_temp.u('sweep'), now(), false);
do $$
declare v jsonb;
begin
  v := search.refresh_course_enrichment_core_scoped_v1(array[pg_temp.u('proj multi'), pg_temp.u('proj sib'), pg_temp.u('proj one'), pg_temp.u('proj prim'), pg_temp.u('proj spell')], false);
  perform pg_temp.ok((select official_course_url from pg_temp.cf_search_enrichment_stage where course_id = pg_temp.u('proj multi')) like '%master-of-media-mc188', 'several links: course_url that passes');
  perform pg_temp.ok((select official_course_url from pg_temp.cf_search_enrichment_stage where course_id = pg_temp.u('proj sib')) like '%master-of-advertising-mc249', 'several links, course_url refused: today''s choice kept, no new null');
  perform pg_temp.ok((select official_course_url from pg_temp.cf_search_enrichment_stage where course_id = pg_temp.u('proj spell')) like '%master-of-design-mc300', 'course_url spelled differently (http, no www, closing slash) still found');
  perform pg_temp.ok((select official_course_url from pg_temp.cf_search_enrichment_stage where course_id = pg_temp.u('proj one')) like '%master-of-advertising-mc249', 'one link: as before');
  perform pg_temp.ok((select official_course_url from pg_temp.cf_search_enrichment_stage where course_id = pg_temp.u('proj prim')) like '%graduate-diploma-in-media-gd180', 'primary: as before');
  v := search.refresh_course_enrichment_core_v1(false);
  perform pg_temp.ok((select official_course_url from pg_temp.cf_search_enrichment_stage where course_id = pg_temp.u('proj sib')) like '%master-of-advertising-mc249'
                     and (select official_course_url from pg_temp.cf_search_enrichment_stage where course_id = pg_temp.u('proj multi')) like '%master-of-media-mc188', 'full refresh: the same rule');
  raise notice 'PASS projection tie-break';
end $$;

-- 15b. merged institutions and second domains: Adelaide University's pages on adelaide.edu.au are its own website ----------------------------
insert into catalogue.providers(id, stable_key, canonical_name, website, lifecycle_status) values
  (pg_temp.u('adelaideuni'), 'provider:cricos:04249j', 'Adelaide University', 'https://adelaideuni.edu.au', 'active'),
  (pg_temp.u('uofa'), 'provider:cricos:00123m', 'The University of Adelaide (Adelaide)', 'http://www.adelaide.edu.au', 'archived'),
  (pg_temp.u('usc senior'), 'provider:cricos:02375g', 'University Senior College at Adelaide University Inc', 'https://www.usc.adelaide.edu.au', 'active'),
  (pg_temp.u('monash'), 'provider:cricos:00008c', 'Monash University', 'https://www.monash.edu.au', 'active'),
  (pg_temp.u('monash college'), 'provider:cricos:01857j', 'Monash College', 'https://www.monash.edu', 'active');
select pg_temp.course('adelaide md', 'adelaideuni', '115787D', 'Doctor of Medicine', 'non_aqf_award'),
       pg_temp.course('monash bcom', 'monash', '000001A', 'Bachelor of Commerce', 'bachelor'),
       pg_temp.course('usc senior y12', 'usc senior', '000002B', 'Year 12', 'senior_secondary_certificate');
do $$
begin
  perform pg_temp.ok(security.course_page_check_v1(pg_temp.u('adelaide md'), 'https://adelaide.edu.au/study/degrees/doctor-of-medicine/int/')->>'rule' <> 'provider', 'Adelaide University on adelaide.edu.au is its own website');
  perform pg_temp.ok(security.course_page_check_v1(pg_temp.u('monash bcom'), 'https://www.monash.edu/study/courses/find-a-course/bachelor-of-commerce-b2001')->>'rule' <> 'provider', 'Monash on monash.edu (alias) is its own website, though another provider uses that host');
  update pipeline.platform_toolset_settings set value = '[]' where key = 'binding.provider_host_aliases';
  perform pg_temp.ok(security.course_page_check_v1(pg_temp.u('monash bcom'), 'https://www.monash.edu/study/courses/find-a-course/bachelor-of-commerce-b2001')->>'rule' = 'provider', 'without the alias, another active provider''s host is refused');
  perform pg_temp.ok(security.course_page_check_v1(pg_temp.u('adelaide md'), 'https://adelaide.edu.au/study/degrees/doctor-of-medicine/int/')->>'rule' <> 'provider', 'an archived provider''s old website is not another provider');
  insert into pipeline.provider_extra_domains values (pg_temp.u('monash'), 'monash.edu', 'mapped');
  perform pg_temp.ok(security.course_page_check_v1(pg_temp.u('monash bcom'), 'https://www.monash.edu/study/courses/find-a-course/bachelor-of-commerce-b2001')->>'rule' <> 'provider', 'an extra course domain a person added counts as the provider''s own');
  perform pg_temp.ok(security.course_page_check_v1(pg_temp.u('usc senior y12'), 'https://adelaideuni.edu.au/study/year-12')->>'rule' = 'provider', 'a different active provider''s website is still refused');
  raise notice 'PASS provider hosts: merged institutions and second domains';
end $$;

-- 15. nothing reaches the signed-in or anonymous roles ----------------------------------------------------------------------------------
do $$
begin
  perform pg_temp.ok(not has_function_privilege('authenticated', 'security.course_page_check_v1(uuid,text,text,text)', 'execute')
                     and not has_function_privilege('service_role', 'security.binding_refusal_route_v1(uuid,text,jsonb,text,uuid)', 'execute'), 'privileges');
  raise notice 'PASS privileges';
end $$;
