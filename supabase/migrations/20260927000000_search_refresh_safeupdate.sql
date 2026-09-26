-- Package 9.1 (R16): register ingestion failed because Supabase's safe-update rule on API sessions
-- (pg safeupdate) refuses UPDATE without WHERE. search.refresh_course_documents_v2 (called by the
-- Layer 1 finaliser) updates its temporary staging table in full. An explicit "where true" keeps the
-- meaning and satisfies the rule. (The projection_state update already has a WHERE.)
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

-- The Layer 1 finaliser (via search.rebuild_course_documents) still called the course-v2 rebuild,
-- while the search projection is course-v3: every ingest would have rewritten all 33,105 documents
-- in the old format. It now calls the current v3 refresh, which writes only changed documents.
-- The v3 enrichment stage update also needs an explicit WHERE for API sessions.
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

-- The v3 base stage update also lacked a WHERE (the statement actually refused during ingest).
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

-- Decision 152: the v3 enrichment step rewrote every consumer document on every refresh
-- (33,105 rows, ~180 MB). It now updates only documents whose enrichment changed, that are not yet
-- course-v3, or that the base v3 step updated earlier in the same refresh (updated_at = now()).
do $patch$
declare d text; n int;
  old_w constant text := 'from cf_search_enrichment_stage s where d.course_id=s.course_id;';
  new_w constant text := 'from cf_search_enrichment_stage s where d.course_id=s.course_id and (d.enrichment_content_hash is distinct from s.enrichment_content_hash or d.projection_version is distinct from ''course-v3'' or d.updated_at = now());';
begin
  select pg_get_functiondef('search.refresh_course_enrichment_core_v1(boolean)'::regprocedure) into d;
  if md5(d) <> '9e339a25d36b7768e9c3e7c2c1589c6a' then raise exception 'refresh_course_enrichment_core_v1 changed since review (md5 %)', md5(d); end if;
  select count(*) into n from regexp_matches(d, 'from\s+cf_search_enrichment_stage\s+s\s+where\s+d\.course_id\s*=\s*s\.course_id\s*;', 'gi');
  if n<>1 then raise exception 'document update condition found % times', n; end if;
  d := regexp_replace(d, 'from\s+cf_search_enrichment_stage\s+s\s+where\s+d\.course_id\s*=\s*s\.course_id\s*;', new_w, 'i');
  execute d;
end $patch$;
