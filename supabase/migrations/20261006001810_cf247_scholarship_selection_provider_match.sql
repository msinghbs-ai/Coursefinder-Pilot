do $p$
declare v_def text; v_new text;
  s1 text := 'or (sc.study_level_id=b.study_level_id and sc.provider_id is null and sc.course_id is null)';
  s2 text := 'or (sc.field_id=b.primary_field_id and sc.provider_id is null and sc.course_id is null)';
  s3 text := 'and sc.study_level_id=b.study_level_id) then 50';
  s4 text := 'and sc.field_id=b.primary_field_id) then 50';
  g text := ' and (s.provider_id is null or s.provider_id=b.provider_id)';
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.scholarship_selection_for_course_impl(uuid)'::regprocedure) is distinct from '3ace946099f640874935d9a3237cea73' then
    raise exception 'scholarship_selection_for_course_impl is not the expected definition; refusing to patch it';
  end if;
  v_def := pg_get_functiondef('security.scholarship_selection_for_course_impl(uuid)'::regprocedure);
  if (length(v_def) - length(replace(v_def, s1, ''))) <> length(s1) or (length(v_def) - length(replace(v_def, s2, ''))) <> length(s2)
     or (length(v_def) - length(replace(v_def, s3, ''))) <> length(s3) or (length(v_def) - length(replace(v_def, s4, ''))) <> length(s4) then
    raise exception 'expected snippets not found exactly once';
  end if;
  v_new := replace(replace(replace(replace(v_def,
    s1, 'or (sc.study_level_id=b.study_level_id and sc.provider_id is null and sc.course_id is null' || g || ')'),
    s2, 'or (sc.field_id=b.primary_field_id and sc.provider_id is null and sc.course_id is null' || g || ')'),
    s3, 'and sc.study_level_id=b.study_level_id' || g || ') then 50'),
    s4, 'and sc.field_id=b.primary_field_id' || g || ') then 50');
  execute v_new;
end $p$;
