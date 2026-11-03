-- The defect on the live definitions: course-relink tries each refused page once, so a course whose page was refused and that the gap queue
-- holds as waiting for page proof is never sent to it again, even when the university's stored lists now hold its address.
set client_min_messages = notice;
do $$
declare v jsonb;
begin
  v := security.course_relink_tick_v1(200);
  if (v->>'providers')::int <> 0 or exists (select 1 from pipeline.course_relink where state <> 'absent') then raise exception 'before: %', v; end if;
  raise notice 'before: % courses wait for page proof; course-relink takes none of them again (tick %); c01''s address is in the stored list', 
    (select count(*) from pipeline.course_page_proofs where not proven), v;
end $$;
