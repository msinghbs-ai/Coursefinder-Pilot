-- CF-247 Decision 253 (4 Oct 2026). University adapters are now used by the page reader and by Read pages, not only on
-- stored pages. Found with the Firecrawl probe: handbooks built in the browser (CourseLoop: Flinders, Macquarie,
-- Murdoch) send every course's data in the page itself (a __NEXT_DATA__ script: title, CRICOS code, IELTS scores,
-- offerings, duration). A plain fetch has it, so these pages need no browser and no Firecrawl credits once the
-- university's adapter knows where the data is. Firecrawl's cleaned HTML leaves that script out, which is why the Read pages
-- pilot saw "Handbook" and refused them.
--   * svc_uni_adapters(): the switched-on adapters, for the worker.
--   * Applying an adapter now also sends that university's pages back to the reader: pages waiting for a browser, and
--     pages refused after a Firecrawl read of cleaned HTML (they are read again from a plain fetch). Logged.
--   * Adapters for Flinders, Macquarie and Murdoch are set up (switched on) for the Platform Admin to review. A page
--     they confirm has the identity basis adapter_code or adapter_title, which no country admission rule allows yet:
--     nothing is admitted from them until the Platform Admin allows it.
-- No text value in this file contains a semicolon.

create or replace function public.svc_uni_adapters() returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return coalesce((select jsonb_object_agg(a.provider_id::text, security.uni_adapter_json(a.provider_id)) from pipeline.uni_adapters a where a.enabled), '{}'::jsonb);
end $f$;
revoke all on function public.svc_uni_adapters() from public, anon, authenticated;
grant execute on function public.svc_uni_adapters() to service_role;

-- Send a university's pages back to the reader so its adapter is used on a fresh plain fetch. Logged per page.
create or replace function security.uni_adapter_requeue_v1(p_provider_id uuid, p_reason text) returns int
language plpgsql security definer set search_path = '' as $f$
declare n int;
begin
  insert into pipeline.page_link_repairs(course_id, provider_id, old_url, new_url, reason)
    select pg.course_id, pg.provider_id, pg.url, pg.url, 'university adapter: page read again (' || p_reason || ')'
    from pipeline.coverage_course_pages pg
    where pg.provider_id = p_provider_id and (pg.read_status = 'needs_render' or (pg.read_status = 'identity_mismatch' and pg.fetched_via = 'firecrawl'))
      and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = pg.course_id and k.field = 'official_url');
  update pipeline.coverage_course_pages pg set status = 'bound', read_status = 'needs_render', next_read_at = now(), leased_until = null where pg.provider_id = p_provider_id and (pg.read_status = 'needs_render' or (pg.read_status = 'identity_mismatch' and pg.fetched_via = 'firecrawl')) and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = pg.course_id and k.field = 'official_url');
  get diagnostics n = row_count;
  return n;
end $f$;
revoke all on function security.uni_adapter_requeue_v1(uuid, text) from public, anon, authenticated;

-- Apply: stored pages (worker) and a fresh read of the pages a plain fetch can now read.
create or replace function public.admin_uni_adapter_write(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_pid uuid := (p_args->>'provider_id')::uuid; v_a jsonb := coalesce(p_args->'adapter', '{}'::jsonb);
        v_id uuid; k text; v text; v_before jsonb; v_n int;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if not exists (select 1 from catalogue.providers p where p.id = v_pid) then raise exception 'unknown provider'; end if;
  if p_action in ('save', 'preview') then
    if jsonb_typeof(coalesce(v_a->'json_paths', '{}'::jsonb)) <> 'object' or jsonb_typeof(coalesce(v_a->'sections', '{}'::jsonb)) <> 'object' then raise exception 'json_paths and sections must be field to text maps'; end if;
    for k, v in select x.key, x.value from jsonb_each_text(coalesce(v_a->'sections', '{}'::jsonb)) x union all select 'title_strip', v_a->>'title_strip' union all select 'course_title_strip', v_a->>'course_title_strip' loop
      if not security.uni_adapter_pattern_ok(v) then raise exception 'the pattern for % cannot be read: %', k, v; end if;
    end loop;
    if coalesce(v_a->>'json_source', '') !~ '^[A-Za-z0-9_-]*$' then raise exception 'the JSON script id may only hold letters, digits, _ and -'; end if;
  end if;
  if p_action = 'save' then
    v_before := security.uni_adapter_json(v_pid);
    insert into pipeline.uni_adapters(provider_id, enabled, title_strip, course_title_strip, json_source, json_paths, sections, section_chars, notes, reason, updated_by, updated_at)
      values (v_pid, coalesce((v_a->>'enabled')::boolean, false), nullif(btrim(v_a->>'title_strip'), ''), nullif(btrim(v_a->>'course_title_strip'), ''), nullif(btrim(v_a->>'json_source'), ''),
              coalesce(v_a->'json_paths', '{}'::jsonb), coalesce(v_a->'sections', '{}'::jsonb), greatest(200, least(coalesce((v_a->>'section_chars')::int, 2000), 10000)), v_a->>'notes', v_reason, auth.uid(), now())
    on conflict (provider_id) do update set enabled = excluded.enabled, title_strip = excluded.title_strip, course_title_strip = excluded.course_title_strip, json_source = excluded.json_source, json_paths = excluded.json_paths, sections = excluded.sections, section_chars = excluded.section_chars, notes = excluded.notes, reason = excluded.reason, updated_by = excluded.updated_by, updated_at = now() where pipeline.uni_adapters.provider_id = excluded.provider_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'uni_adapter_save', v_pid::text, jsonb_build_object('before', v_before, 'after', security.uni_adapter_json(v_pid), 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'adapter', security.uni_adapter_json(v_pid));
  elsif p_action = 'preview' then
    insert into pipeline.uni_adapter_previews(provider_id, adapter, requested_by) values (v_pid, v_a, auth.uid()) returning id into v_id;
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_preview', 'preview_id', v_id));
    return jsonb_build_object('ok', true, 'preview_id', v_id);
  elsif p_action = 'apply' then
    if not exists (select 1 from pipeline.uni_adapters a where a.provider_id = v_pid and a.enabled) then raise exception 'save the adapter switched on first'; end if;
    v_n := security.uni_adapter_requeue_v1(v_pid, v_reason);
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'uni_adapter_apply', v_pid::text, jsonb_build_object('adapter', security.uni_adapter_json(v_pid), 'pages_read_again', v_n, 'reason', v_reason), auth.uid());
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_apply', 'provider_id', v_pid));
    return jsonb_build_object('ok', true, 'pages_read_again', v_n);
  end if;
  raise exception 'unknown action';
end $f$;
revoke all on function public.admin_uni_adapter_write(text, jsonb) from public, anon;
grant execute on function public.admin_uni_adapter_write(text, jsonb) to authenticated;

-- CourseLoop handbooks: the page's own data (paths confirmed with the probe on Flinders BAF and Macquarie C000009).
insert into pipeline.uni_adapters(provider_id, enabled, json_source, json_paths, notes, reason, updated_at)
select p.id, true, '__NEXT_DATA__',
       '{"title":"props.pageProps.pageContent.title","code":"props.pageProps.pageContent.cricos_code","ielts_overall":"props.pageProps.pageContent.ielts_overall_score","english":"props.pageProps.pageContent.english_language_requirements","intakes":"props.pageProps.pageContent.offering","duration":"props.pageProps.pageContent.duration_ft_std"}'::jsonb,
       'CourseLoop handbook. The course data is in the page (script __NEXT_DATA__), so a plain fetch reads it.', 'Decision 253: set up by Claude for the Platform Admin to review', now()
from catalogue.providers p where p.id in ('0a42da16-8df1-4439-a929-4dfdd04b6d83', '188103a5-1aba-4f99-bd3e-0416659086d3', (select p2.id from catalogue.providers p2 where p2.canonical_name = 'Murdoch University' limit 1))
on conflict (provider_id) do nothing;

select security.uni_adapter_requeue_v1(a.provider_id, 'adapter set up, Decision 253') from pipeline.uni_adapters a where a.enabled;
