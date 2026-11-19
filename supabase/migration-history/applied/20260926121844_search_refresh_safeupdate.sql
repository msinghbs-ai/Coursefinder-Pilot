do $patch$
declare d text; n int; stmt text;
begin
  select pg_get_functiondef('search.refresh_course_documents_v2(boolean)'::regprocedure) into d;
  if md5(d) <> '30d294edc08dfc31781b3312273a7fd4' then raise exception 'refresh_course_documents_v2 changed since review (md5 %)', md5(d); end if;
  select count(*) into n from regexp_matches(d, 'update\s+cf_search_course_stage\s+s\s+set\s+semantic_content_hash[^;]*;', 'gi');
  if n<>1 then raise exception 'stage update found % times', n; end if;
  stmt := substring(d from '(?i)(update\s+cf_search_course_stage\s+s\s+set\s+semantic_content_hash[^;]*;)');
  if stmt ~* '\)\s*where\s' or stmt ~* '''hex''\)\s+where' then raise exception 'stage update already has a WHERE'; end if;
  d := regexp_replace(d, '(update\s+cf_search_course_stage\s+s\s+set\s+semantic_content_hash[^;]*);', '\1 where true;', 'i');
  execute d;
end $patch$;
