-- CF-247 scholarship course links, fix (1 Oct 2026): the name-based suggestion added reasons to a text array with ||,
-- which Postgres read as an array literal ("malformed array literal") and the Course links list failed to load.
-- Uses array_append instead. md5-guarded in-place edit of security.scholarship_scope_suggest.
do $$
declare d text; n text;
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.scholarship_scope_suggest(uuid)'::regprocedure) <> '47fc4f2ab27d7a2d3c7f466e029b55b1' then
    raise exception 'scholarship_scope_suggest changed; review first';
  end if;
  d := pg_get_functiondef('security.scholarship_scope_suggest(uuid)'::regprocedure);
  n := replace(d, $x$v_why := v_why || 'research degrees'$x$, $x$v_why := array_append(v_why, 'research degrees')$x$);
  n := replace(n, $x$v_why := v_why || 'undergraduate courses'$x$, $x$v_why := array_append(v_why, 'undergraduate courses')$x$);
  n := replace(n, $x$v_why := v_why || 'postgraduate coursework'$x$, $x$v_why := array_append(v_why, 'postgraduate coursework')$x$);
  n := replace(n, $x$v_why := v_why || 'the field named in the title'$x$, $x$v_why := array_append(v_why, 'the field named in the title')$x$);
  if position('v_why || ' in n) > 0 or (length(n) - length(replace(n, 'array_append(v_why', ''))) / length('array_append(v_why') <> 4 then raise exception 'edit did not apply'; end if;
  execute n;
end $$;
