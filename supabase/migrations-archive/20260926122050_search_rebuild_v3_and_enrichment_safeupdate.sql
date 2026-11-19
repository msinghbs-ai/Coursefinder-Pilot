do $patch$
declare d text; n int;
begin
  select pg_get_functiondef('search.refresh_course_enrichment_core_v1(boolean)'::regprocedure) into d;
  if md5(d) <> '47dbbb6a69b98fe5c6f98905a5e03a90' then raise exception 'refresh_course_enrichment_core_v1 changed since review (md5 %)', md5(d); end if;
  select count(*) into n from regexp_matches(d, 'update\s+cf_search_enrichment_stage\s+s\s+set\s+enrichment_content_hash[^;]*;', 'gi');
  if n<>1 then raise exception 'enrichment stage update found % times', n; end if;
  if substring(d from '(?i)(update\s+cf_search_enrichment_stage\s+s\s+set\s+enrichment_content_hash[^;]*;)') ~* '\swhere\s' then raise exception 'enrichment stage update already has a WHERE'; end if;
  d := regexp_replace(d, '(update\s+cf_search_enrichment_stage\s+s\s+set\s+enrichment_content_hash[^;]*);', '\1 where true;', 'i');
  execute d;
  if md5(pg_get_functiondef('search.rebuild_course_documents()'::regprocedure)) <> '6378e29fed355c54d86e1a4b8aef140a' then raise exception 'rebuild_course_documents changed since review'; end if;
end $patch$;

create or replace function search.rebuild_course_documents()
returns bigint language plpgsql security definer
set search_path to 'search'
as $$
declare v_result jsonb;
begin
  v_result := search.refresh_course_documents_v3(true);
  return (v_result->'base'->>'stage_count')::bigint;
end $$;
revoke all on function search.rebuild_course_documents() from public, anon, authenticated;
grant execute on function search.rebuild_course_documents() to service_role;
