-- CF-247 Decision 254 (5 Oct 2026, Platform Admin 13:02). The international view applies only to the pages it names.
-- La Trobe's first read with the view (13:40) also sent its handbook pages through the view, and pages already tried
-- three times were never read again. Now:
--   page_view.url_pattern (optional) names the pages that show the view (La Trobe "^https://www\.latrobe\.edu\.au/courses/").
--   Worker v0.17.5 reads only those pages with the view, and other pages as before.
--   read_view sends back the named pages with their tries reset. Pages outside the pattern that an earlier view read left
--   unread are also sent back, to be read the usual way.
-- No text value in this file contains a semicolon. Snippet patches are md5-guarded and each is found exactly once.

do $p$
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.uni_adapter_view_requeue_v1(uuid,text,int)'::regprocedure) is distinct from '92c9d5f95a08864f16652ca40e6192ac' then
    raise exception 'uni_adapter_view_requeue_v1 changed, not replacing'; end if;
end $p$;

create or replace function security.uni_adapter_view_requeue_v1(p_provider_id uuid, p_reason text, p_limit int default 600) returns integer
language plpgsql security definer set search_path = '' as $f$
declare n int; v_ids uuid[]; v_pat text;
begin
  select coalesce(nullif(btrim(u.page_view->>'url_pattern'), ''), '.') into v_pat from pipeline.uni_adapters u
   where u.provider_id = p_provider_id and u.enabled and coalesce(u.page_view->>'render', 'false') = 'true';
  if v_pat is null then raise exception 'the adapter names no international view to read'; end if;
  v_ids := array(select pg.course_id from pipeline.coverage_course_pages pg join pipeline.uni_adapters u on u.provider_id = pg.provider_id
                  join catalogue.courses co on co.id = pg.course_id and co.lifecycle_status = 'active'
                  where pg.provider_id = p_provider_id and pg.url is not null
                    and ((pg.url ~* v_pat and pg.read_status in ('read', 'identity_mismatch', 'needs_render', 'fetch_failed', 'blocked')
                          and (pg.read_at is null or pg.read_at < u.updated_at))
                      or (pg.url !~* v_pat and pg.read_status <> 'read'
                          and exists (select 1 from pipeline.page_link_repairs x where x.course_id = pg.course_id and x.reason like 'university adapter: international view read%')))
                  order by pg.course_id limit greatest(1, least(coalesce(p_limit, 600), 600)));
  insert into pipeline.page_link_repairs(course_id, provider_id, old_url, new_url, reason)
    select pg.course_id, pg.provider_id, pg.url, pg.url, case when pg.url ~* v_pat then 'university adapter: international view read (' else 'university adapter: read again outside the international view (' end || left(p_reason, 300) || ')'
    from pipeline.coverage_course_pages pg where pg.course_id = any (v_ids);
  update pipeline.coverage_course_pages pg set status = 'bound', read_status = 'needs_render', read_attempts = 0, next_read_at = now(), leased_until = null where pg.course_id = any (v_ids);
  get diagnostics n = row_count;
  return n;
end $f$;
revoke all on function security.uni_adapter_view_requeue_v1(uuid, text, int) from public, anon, authenticated;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_uni_adapter_write(text,jsonb)'::regprocedure) is distinct from 'dcc121c91b17840fe9d999786e217e9d' then
    raise exception 'admin_uni_adapter_write changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_uni_adapter_write(text,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$or coalesce(v_a->'page_view'->>'render', 'false') not in ('true', 'false') then$s$,
          $s$or coalesce(v_a->'page_view'->>'render', 'false') not in ('true', 'false') or not security.uni_adapter_pattern_ok(v_a->'page_view'->>'url_pattern') then$s$],
    array[$s$'page_view must hold render (true or false), suffix (starting with # ? or &) and wait_ms (0 to 8000)'$s$,
          $s$'page_view must hold render (true or false), suffix (starting with # ? or &), wait_ms (0 to 8000) and a readable url_pattern'$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;
