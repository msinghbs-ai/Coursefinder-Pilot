-- CF-247 Decision 254 (5 Oct 2026, Platform Admin 21:04): "Deploy a button that can force reread pages for one or
-- in bulk for all selected unis".
-- public.admin_university_reread('preview' | 'queue', {provider_ids, which, central, reason}):
--   which = 'all'           every course page of the university
--           'not_confirmed' pages not read or whose identity was not confirmed
--   central = true          the university's central pages (English requirements, key dates) too
-- 'preview' (Layer 4 reviewer and above) counts the pages and the likely Firecrawl credits without changing anything.
-- 'queue' (Platform Admin, with a reason) sends the pages back to the reader now: course pages go to the worker
-- queue (read again even after three failed attempts), central pages are read again by the central page reader.
-- The worker decides how each page is read (plain fetch, or Firecrawl where the page needs rendering, was rendered
-- before or the adapter names an international view), so the credits are an estimate. Every page sent back is
-- logged with the reason. Course pages without an address are left out. No text value in this file contains a
-- semicolon.

create or replace function security.university_reread_pages_v1(p_provider_ids uuid[], p_which text)
returns table(provider_id uuid, course_id uuid, url text, firecrawl_likely boolean)
language sql stable security definer set search_path = '' as $f$
  select pg.provider_id, pg.course_id, pg.url,
         (pg.fetched_via = 'firecrawl' or pg.read_status in ('needs_render', 'blocked')
          or exists (select 1 from pipeline.uni_adapters u where u.provider_id = pg.provider_id and u.enabled and coalesce(u.page_view->>'render', 'false') = 'true'
                       and pg.url ~* coalesce(nullif(btrim(u.page_view->>'url_pattern'), ''), '.'))) firecrawl_likely
    from pipeline.coverage_course_pages pg join catalogue.courses co on co.id = pg.course_id and co.lifecycle_status = 'active'
   where pg.provider_id = any (p_provider_ids) and coalesce(btrim(pg.url), '') <> ''
     and (coalesce(p_which, 'all') = 'all' or pg.read_status is distinct from 'read' or pg.identity_basis is null)
$f$;
revoke all on function security.university_reread_pages_v1(uuid[], text) from public, anon, authenticated;

create or replace function public.admin_university_reread(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare
  v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', ''));
  v_ids uuid[]; v_which text := coalesce(nullif(p_args->>'which', ''), 'all'); v_central boolean := coalesce((p_args->>'central')::boolean, false);
  v_res jsonb; v_pages int := 0; v_cent int := 0;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'Layer 4 reviewer or Platform Admin required' using errcode = '42501'; end if;
  if v_which not in ('all', 'not_confirmed') then raise exception 'which must be all or not_confirmed'; end if;
  v_ids := array(select distinct (x)::uuid from jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb)) x);
  if cardinality(v_ids) = 0 then raise exception 'choose at least one university'; end if;
  if p_action = 'preview' then
    return jsonb_build_object('which', v_which, 'central', v_central,
      'universities', coalesce((select jsonb_agg(jsonb_build_object('provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name),
                         'pages', (select count(*) from security.university_reread_pages_v1(array[p.id], v_which)),
                         'firecrawl_likely', (select count(*) from security.university_reread_pages_v1(array[p.id], v_which) r where r.firecrawl_likely),
                         'central_pages', case when v_central then (select count(*) from pipeline.provider_fact_sources fs where fs.provider_id = p.id and fs.kind in ('english_policy', 'intake_calendar')) else 0 end)
                         order by coalesce(p.display_name, p.canonical_name)) from catalogue.providers p where p.id = any (v_ids)), '[]'::jsonb));
  end if;
  if coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action <> 'queue' then raise exception 'unknown action'; end if;
  insert into pipeline.page_link_repairs(course_id, provider_id, old_url, new_url, reason)
    select r.course_id, r.provider_id, r.url, r.url, 'read again by a Platform Admin (' || left(v_reason, 300) || ')'
      from security.university_reread_pages_v1(v_ids, v_which) r;
  update pipeline.coverage_course_pages pg set status = 'bound', read_attempts = 0, next_read_at = now(), leased_until = null where pg.course_id in (select r.course_id from security.university_reread_pages_v1(v_ids, v_which) r);
  get diagnostics v_pages = row_count;
  if v_central then
    update pipeline.provider_fact_sources fs set status = 'found', attempts = 0, updated_at = now() where fs.provider_id = any (v_ids) and fs.kind in ('english_policy', 'intake_calendar');
    get diagnostics v_cent = row_count;
  end if;
  v_res := jsonb_build_object('ok', true, 'universities', cardinality(v_ids), 'pages', v_pages, 'central_pages', v_cent);
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('coverage', 'university_reread', array_to_string(v_ids, ','), jsonb_build_object('result', v_res, 'args', p_args), auth.uid());
  return v_res;
end $f$;
revoke all on function public.admin_university_reread(text, jsonb) from public, anon;
grant execute on function public.admin_university_reread(text, jsonb) to authenticated;
