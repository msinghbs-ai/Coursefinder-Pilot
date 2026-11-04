-- Capture full authoritative verdict + diagnostics across representative existing and dense pages.
create table public.fixture_identity_golden as
select g.course_id,g.url,security.course_page_check_v1(g.course_id,g.url,null,null) result
from pipeline.coverage_course_pages g where g.course_id not in(select id from catalogue.courses where course_code like 'DC%' or course_code like 'DX%')
union all
select g.course_id,g.url,security.course_page_check_v1(g.course_id,g.url,null,null)
from pipeline.coverage_course_pages g where g.course_id in(select id from catalogue.courses where course_code like 'DC%' order by id limit 3)
union all select g.course_id,g.url,security.course_page_check_v1(g.course_id,g.url,null,null)
from pipeline.coverage_course_pages g where g.course_id in(select id from catalogue.courses where course_code like 'DX%' order by id limit 3);
