-- Before workstream F (live definitions as read 3 Nov 2026): the waste is paid for and nothing measures it.
select fx.reset();
select fx.ok(fx.spend('course_link_search', fx.p(1), '"Bachelor of Applied Management" site:example.ac.nz', 2), 'before: a course-page search is paid for');
select fx.ok(fx.spend('course_link_search', fx.p(1), '"Bachelor of Applied Management" site:example.ac.nz', 2), 'before: the identical search one minute later is paid for again (repeat with no new input)');
insert into pipeline.evidence_artifacts(source_url, content_hash, captured_at) values ('https://example.ac.nz/courses/bam', 'h1', now() - interval '3 hours');
select fx.ok(fx.spend('scrape', fx.p(1), 'https://example.ac.nz/courses/bam'), 'before: a page stored 3 hours ago is bought again');
select fx.ok(not fx.spend('course_link_search', fx.p(2), '"Diploma" site:stopped.example', 2), 'before: the existing stop gate refuses a course-page search of a search-stopped provider');
select fx.ok(fx.spend('fc_search', fx.p(2), '"Diploma" site:stopped.example', 2), 'before: the same search through another purpose (fc_search) is paid for');
select fx.ok((select count(*) from pipeline.coverage_vendor_usage) = 4, 'before: four paid operations recorded');
select fx.ok(not (security.waste_guard_v1() ? 'cost'), 'before: the waste guard has no cost checks');
