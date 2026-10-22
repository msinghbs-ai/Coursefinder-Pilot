-- CF-247 (23 Oct 2026). Course source finder, second test run (Simon Fraser University): the course pages already found were stored at
-- old addresses (students.sfu.ca/calendar/..., www.sfu.ca/calendar/...) that now redirect, so the address pattern the finder learnt from
-- them matched nothing on the live site. The finder now learns from the address each page was actually read at (the evidence copy's
-- source_url), with the stored address kept as the fallback.
-- Replaces: nothing (public.svc_source_find_next edited in place, md5-guarded)
-- Retires: nothing
do $do$
declare v_def text := pg_get_functiondef('public.svc_source_find_next(integer,uuid[])'::regprocedure);
  v_old text := $o$select distinct pg.url u from pipeline.coverage_course_pages pg where pg.provider_id = p.id and pg.status = 'bound' and pg.read_status = 'read' and pg.url is not null$o$;
  v_new text := $n$select distinct coalesce(e.source_url, pg.url) u from pipeline.coverage_course_pages pg left join pipeline.evidence_artifacts e on e.id = pg.evidence_id where pg.provider_id = p.id and pg.status = 'bound' and pg.read_status = 'read' and coalesce(e.source_url, pg.url) is not null$n$;
begin
  if md5(v_def) <> 'b767c585604a4cb47934a02cc3e37562' then raise exception 'public.svc_source_find_next is not the expected version (md5 %)', md5(v_def); end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'source find next: expected one known-pages query'; end if;
  execute replace(v_def, v_old, v_new);
end $do$;

select 'source finder learns from landing addresses' ok;

do $t$ declare v jsonb; begin
  v := public.svc_source_find_next(1, array['d47b6006-396a-4785-b2ae-15186c3e7709'::uuid]);
  raise exception 'DRYRUN OK %', (select jsonb_agg(u) from (select jsonb_array_elements_text(x->'known') u from jsonb_array_elements(v->'items') x limit 4) z); end $t$;
