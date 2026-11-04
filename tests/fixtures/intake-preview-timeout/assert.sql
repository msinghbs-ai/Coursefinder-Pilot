\set ON_ERROR_STOP on
do $$ declare n integer; begin
 select count(*) into n from public.fixture_identity_golden;
 if exists(select 1 from public.fixture_identity_golden g where security.course_page_check_v1(g.course_id,g.url,null,null) is distinct from g.result) then raise exception 'identity verdict/diagnostic changed'; end if;
 if exists(select 1 from (values(''),('A'),('Art'),('Arts'),('Master of X'),('A & B'),('X_Y'),('100% course'),('日本'),('Éducation'),('a.b-c')) a(title)
 cross join (values(''),('a'),('art'),('arts'),('master-of-x-course'),('a-and-b-code'),('x-y'),('100-course'),('ducation')) b(slug)
 where (b.slug like replace(security.course_title_key(a.title),' ','-')||'%') is distinct from
 (replace(security.course_title_key(a.title),' ','-')=any(array(select left(b.slug,i) from generate_series(0,length(b.slug)) i)))) then raise exception 'prefix lookup equivalence failed'; end if;
 if security.intake_ui_selection_v1('top-au',20)->'courses' is distinct from (select courses from public.fixture_preview_members_golden) then raise exception 'selected courses or source-supported values changed';end if;
 if (select jsonb_array_length(security.intake_ui_selection_v1('top-au',20)->'courses'))<>20 then raise exception 'work cap reduced selected cohort'; end if;
 if exists(select 1 from jsonb_array_elements(security.intake_ui_selection_v1('top-au',20)->'universities') u where (u->>'scan_limit')::int<>5) then raise exception 'actual/displayed work cap mismatch';end if;
 raise notice 'PASS % authoritative verdict/diagnostic comparisons, prefix edge cases, twenty-course selection and displayed work limits',n;
end $$;
