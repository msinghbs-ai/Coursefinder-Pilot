do $p$
declare v_def text; v_new text;
  s1 text := '(inc.study_level_id is not null and inc.study_level_id=v_level)';
  s2 text := '(inc.field_id is not null and inc.field_id=v_field)';
  g text := ' and (s.provider_id is null or s.provider_id=v_provider)';
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.admin_contextual_insights(text,uuid)'::regprocedure) is distinct from '60ca16d244029dad671c8d838558fb6b' then
    raise exception 'admin_contextual_insights is not the expected definition; refusing to patch it';
  end if;
  v_def := pg_get_functiondef('security.admin_contextual_insights(text,uuid)'::regprocedure);
  if (length(v_def) - length(replace(v_def, s1, ''))) <> 2 * length(s1) or (length(v_def) - length(replace(v_def, s2, ''))) <> 2 * length(s2) then
    raise exception 'expected snippets not found exactly twice';
  end if;
  v_new := replace(replace(v_def,
    s1, '(inc.study_level_id is not null and inc.study_level_id=v_level' || g || ')'),
    s2, '(inc.field_id is not null and inc.field_id=v_field' || g || ')');
  execute v_new;
end $p$;
