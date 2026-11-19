do $patch$
declare d text; n int;
begin
  select pg_get_functiondef('search.refresh_course_base_v3(boolean)'::regprocedure) into d;
  if md5(d) <> 'af7c3fbb38f2d2bcc5ed144c09c15ae3' then raise exception 'refresh_course_base_v3 changed since review (md5 %)', md5(d); end if;
  select count(*) into n from regexp_matches(d, 'update\s+cf_search_course_base_v3_stage\s+s\s+set\s+semantic_content_hash[^;]*;', 'gi');
  if n<>1 then raise exception 'base stage update found % times', n; end if;
  if substring(d from '(?i)(update\s+cf_search_course_base_v3_stage\s+s\s+set\s+semantic_content_hash[^;]*;)') ~* '''hex''\)\s*where\s' then raise exception 'base stage update already has a WHERE'; end if;
  d := regexp_replace(d, '(update\s+cf_search_course_base_v3_stage\s+s\s+set\s+semantic_content_hash[^;]*);', '\1 where true;', 'i');
  execute d;
end $patch$;
