-- CF-247 (3 Oct 2026, 22:00 AEST). The Scholarships list and the scholarship record show the nationalities read from
-- wording (Decision 246) beside the audience. Both reads are replaced under md5 guards; one column is added to each.
do $g$ declare v_oid oid; v_def text; begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.proname = 'admin_scholarships_page';
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from 'd5ac6ad770a3a49e31c814c787f136d3' then raise exception 'admin_scholarships_page changed; not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  if (select count(*) from regexp_matches(v_def, 's\.audience,s\.award_value_text,', 'g')) <> 1 then raise exception 'admin_scholarships_page column list not found exactly once'; end if;
  execute replace(v_def, 's.audience,s.award_value_text,', 's.audience,s.nationalities,s.award_value_text,');

  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'ui_scholarship_detail';
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from 'eab20777badd0342adc81d87d2b6709b' then raise exception 'ui_scholarship_detail changed; not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  if (select count(*) from regexp_matches(v_def, '''audience'',s\.audience,', 'g')) <> 1 then raise exception 'ui_scholarship_detail audience key not found exactly once'; end if;
  execute replace(v_def, $x$'audience',s.audience,$x$, $x$'audience',s.audience,'nationalities',s.nationalities,'award_value_is_maximum',s.award_value_is_maximum,$x$);
end $g$;
