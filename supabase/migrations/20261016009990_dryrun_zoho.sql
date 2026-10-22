-- CF-247 (22 Oct 2026). Found after the first live scope gate run: the website search copy (search.course_documents) is refreshed only
-- on a request, so the 1,421 Canadian courses hidden or shown kept their old place on the website until a request was added by hand.
-- The gate now asks for a search refresh whenever it hides or shows a course.
-- Replaces: security.country_scope_gate_v1 (md5-guarded edit)
-- Retires: nothing
do $edit$
declare v_def text := pg_get_functiondef('security.country_scope_gate_v1(boolean,text)'::regprocedure);
        v_old text := $o$    select count(*) into v_show from l;
  end if;$o$;
begin
  if position('search.refresh_requests' in v_def) > 0 then return; end if;
  if md5(v_def) <> '585dcb3fd275e206afe1b107f46b7ee4' then raise exception 'live security.country_scope_gate_v1 differs from the definition this change edits'; end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'end of apply must occur once'; end if;
  execute replace(v_def, v_old, $n$    select count(*) into v_show from l;
    if v_hide + v_show > 0 then
      insert into search.refresh_requests(requested_by) values ('country scope gate ' || p_country || ' (' || v_tag || '): ' || v_hide || ' hidden, ' || v_show || ' shown');
    end if;
  end if;$n$);
end $edit$;
do $dry$ begin raise exception 'DRYRUN OK %', position('search.refresh_requests' in pg_get_functiondef('security.country_scope_gate_v1(boolean,text)'::regprocedure)) > 0; end $dry$;
