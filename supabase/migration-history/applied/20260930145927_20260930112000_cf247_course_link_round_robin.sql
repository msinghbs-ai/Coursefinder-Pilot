-- CF-247 course link recipes, follow-up (1 Oct 2026): send searches across the ten universities in turn rather than one
-- university at a time. The page reader takes at most 8 pages per university per run, so one university at a time left
-- found pages waiting to be read. md5-guarded in-place edit of security.course_link_search_tick_v1.
do $$
declare v_src text; v_def text; v_old text; v_new text;
begin
  select prosrc, pg_get_functiondef(oid) into v_src, v_def from pg_proc where oid = 'security.course_link_search_tick_v1(int)'::regprocedure;
  if md5(v_src) <> 'd6ca4ee5106f7d7fd9e02fb050b24a14' then raise exception 'course_link_search_tick_v1 changed (md5 %)', md5(v_src); end if;
  v_old := $x$order by (s.stage <> 'cricos'), coalesce(pp.rank, 100000), md5(s.course_id::text)$x$;
  v_new := $x$order by (s.stage <> 'cricos'), row_number() over (partition by s.provider_id order by md5(s.course_id::text)), coalesce(pp.rank, 100000)$x$;
  if position(v_old in v_def) = 0 then raise exception 'anchor not found'; end if;
  execute replace(v_def, v_old, v_new);
end $$;
