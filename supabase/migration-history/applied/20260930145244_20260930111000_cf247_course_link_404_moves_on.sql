-- CF-247 course link recipes, follow-up (1 Oct 2026): a candidate page that answers 404 or 410 is gone (typically a
-- retired program whose old handbook entry was moved to this year's edition), so the link search moves to the next
-- candidate at once instead of waiting for a second read six hours later. md5-guarded in-place edit.
do $$
declare v_src text; v_def text; v_old text; v_new text;
begin
  select prosrc, pg_get_functiondef(oid) into v_src, v_def from pg_proc where oid = 'security.course_link_search_tick_v1(int)'::regprocedure;
  if md5(v_src) <> '32703cc75b331849629520359b169ecc' then raise exception 'course_link_search_tick_v1 changed (md5 %)', md5(v_src); end if;
  v_old := $x$(p.read_status in ('fetch_failed','blocked','robots_disallowed') and p.read_attempts >= 2)$x$;
  v_new := $x$(p.read_status in ('fetch_failed','blocked','robots_disallowed') and (p.read_attempts >= 2 or p.http_status in (404, 410)))$x$;
  if position(v_old in v_def) = 0 then raise exception 'anchor not found'; end if;
  execute replace(v_def, v_old, v_new);
end $$;
