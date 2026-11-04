-- Controlled local fixtures; never run on a Supabase project. Existing calendar parser/source fixture is retained.
select pg_temp.course('ui exact','harbour','harbour.edu.au','UI101','Master of Intake Validation','Semester 1'),
       pg_temp.course('ui missing','nocal','inland.edu.au','UI102','Master of Missing Calendar','Semester 1'),
       pg_temp.course('ui locked','harbour','harbour.edu.au','UI103','Master of Locked Dates','Semester 1');
select pg_temp.intake('ui exact','March'),pg_temp.intake('ui missing','March'),pg_temp.intake('ui locked','March');
insert into pipeline.manual_locks values('course',pg_temp.u('ui locked'),'intakes');
insert into security.roles values('operator',3,'active') on conflict do nothing;
insert into security.user_roles values(pg_temp.u('reader'),'operator',null),(pg_temp.u('other admin'),'platform_admin',null);
-- The base harness intentionally records refresh calls. For this vertical test execute its REAL core projection in that hook.
create or replace function search.refresh_course_enrichment_scoped_v1(p_ids uuid[],p_apply boolean) returns jsonb
language plpgsql as $$
declare r jsonb;
begin
 insert into public.fixture_refresh_calls(course_ids) values(p_ids);
 r:=search.refresh_course_enrichment_core_scoped_v1(p_ids,false);
 update search.course_documents d set intake_options=s.intake_options,earliest_intake_date=s.earliest_intake_date,has_intake=jsonb_array_length(s.intake_options)>0
 from cf_search_enrichment_stage s where d.course_id=s.course_id;
 return r;
end $$;
-- Fixture infrastructure grants only; production already exposes public RPCs to authenticated.
grant usage on schema public,auth to authenticated;
grant execute on function auth.uid() to authenticated;
