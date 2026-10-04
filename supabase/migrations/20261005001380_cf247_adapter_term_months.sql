-- CF-247 Decision 254 (5 Oct 2026). From waves 1 and 2 (Melbourne, Macquarie, Canterbury, Simon Fraser, ANU, UTS, UWA,
-- Murdoch, Auckland, Mount Royal).
--   * Most universities print teaching periods, not months: "Autumn Session", "Semester 1", "Fall 2027". An adapter now
--     holds term_months, the university's own published mapping of term names to months (for example Semester 1 =
--     February, set from its key-dates page). The worker (v0.17.3) turns term names found by the intakes pattern into
--     those months. The mapping is set in the UI with a reason and logged like the rest of the adapter.
--   * Applying an adapter sent Firecrawl-refused pages back to the reader, which reads them again through Firecrawl
--     (Auckland: 129 pages, Mount Royal: 5 credits for nothing). They are now sent back only when the adapter reads page
--     data (the reason they were sent back at all: handbooks whose Firecrawl copy lost the page data).
-- md5-guarded whole replacements. No text value in this file contains a semicolon.

alter table pipeline.uni_adapters add column if not exists term_months jsonb not null default '{}'::jsonb;

do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'security.uni_adapter_json(uuid)'::regprocedure) is distinct from '6820d3a50e79c62c05c85ad0f2de9a2e' then
    raise exception 'uni_adapter_json changed, not replacing'; end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_uni_adapter_write(text,jsonb)'::regprocedure) is distinct from 'd052e28f18c9b9481912fb65f490b20d' then
    raise exception 'admin_uni_adapter_write changed, not replacing'; end if;
  if (select md5(prosrc) from pg_proc where oid = 'security.uni_adapter_requeue_v1(uuid,text)'::regprocedure) is distinct from 'be361a8f72c818d6f00c21f727f97c69' then
    raise exception 'uni_adapter_requeue_v1 changed, not replacing'; end if;
end $g$;
create or replace function security.uni_adapter_json(p_provider uuid) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('title_strip', a.title_strip, 'course_title_strip', a.course_title_strip, 'json_source', a.json_source, 'json_paths', a.json_paths,
                            'sections', a.sections, 'patterns', a.patterns, 'pick', a.pick, 'term_months', a.term_months, 'section_chars', a.section_chars, 'enabled', a.enabled, 'notes', a.notes, 'reason', a.reason, 'updated_at', a.updated_at)
  from pipeline.uni_adapters a where a.provider_id = p_provider
$f$;
revoke all on function security.uni_adapter_json(uuid) from public, anon, authenticated;

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
    if jsonb_typeof(coalesce(v_a->'patterns', '{}'::jsonb)) <> 'object' or jsonb_typeof(coalesce(v_a->'pick', '{}'::jsonb)) <> 'object' then raise exception 'patterns and pick must be field to text maps'; end if;
    for k, v in select x.key, x.value from jsonb_each_text(coalesce(v_a->'patterns', '{}'::jsonb)) x loop
      if k <> all (security.uni_adapter_pattern_fields()) then raise exception 'a pattern can only be set for: %', array_to_string(security.uni_adapter_pattern_fields(), ', '); end if;
      if not security.uni_adapter_pattern_ok(v) then raise exception 'the pattern for % cannot be read: %', k, v; end if;
    end loop;
    for k, v in select x.key, x.value from jsonb_each_text(coalesce(v_a->'pick', '{}'::jsonb)) x loop
      if v not in ('first', 'last', 'all') then raise exception 'pick for % must be first, last or all', k; end if;
    end loop;
    if jsonb_typeof(coalesce(v_a->'term_months', '{}'::jsonb)) <> 'object' then raise exception 'term_months must be a term to month map'; end if;
    for k, v in select x.key, x.value from jsonb_each_text(coalesce(v_a->'term_months', '{}'::jsonb)) x loop
      if length(btrim(k)) < 3 or length(k) > 40 then raise exception 'a term name must be 3 to 40 characters: %', k; end if;
      if v !~ '^(January|February|March|April|May|June|July|August|September|October|November|December)( (January|February|March|April|May|June|July|August|September|October|November|December))*$' then raise exception 'the months for % must be month names separated by spaces: %', k, v; end if;
    end loop;
    if coalesce(v_a->>'json_source', '') !~ '^[A-Za-z0-9_-]*$' then raise exception 'the JSON script id may only hold letters, digits, _ and -'; end if;
  end if;
  if p_action = 'save' then
    v_before := security.uni_adapter_json(v_pid);
    insert into pipeline.uni_adapters(provider_id, enabled, title_strip, course_title_strip, json_source, json_paths, sections, patterns, pick, term_months, section_chars, notes, reason, updated_by, updated_at)
      values (v_pid, coalesce((v_a->>'enabled')::boolean, false), nullif(btrim(v_a->>'title_strip'), ''), nullif(btrim(v_a->>'course_title_strip'), ''), nullif(btrim(v_a->>'json_source'), ''),
              coalesce(v_a->'json_paths', '{}'::jsonb), coalesce(v_a->'sections', '{}'::jsonb), coalesce(v_a->'patterns', '{}'::jsonb), coalesce(v_a->'pick', '{}'::jsonb), coalesce(v_a->'term_months', '{}'::jsonb), greatest(200, least(coalesce((v_a->>'section_chars')::int, 2000), 10000)), v_a->>'notes', v_reason, auth.uid(), now())
    on conflict (provider_id) do update set enabled = excluded.enabled, title_strip = excluded.title_strip, course_title_strip = excluded.course_title_strip, json_source = excluded.json_source, json_paths = excluded.json_paths, sections = excluded.sections, patterns = excluded.patterns, pick = excluded.pick, term_months = excluded.term_months, section_chars = excluded.section_chars, notes = excluded.notes, reason = excluded.reason, updated_by = excluded.updated_by, updated_at = now() where pipeline.uni_adapters.provider_id = excluded.provider_id;
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

create or replace function security.uni_adapter_requeue_v1(p_provider_id uuid, p_reason text) returns int
language plpgsql security definer set search_path = '' as $f$
declare n int; v_ids uuid[];
begin
  -- 5 Oct: a page refused after a Firecrawl read is sent back once only, and only when the adapter reads page data
  v_ids := array(select pg.course_id from pipeline.coverage_course_pages pg
                  where pg.provider_id = p_provider_id and (pg.read_status = 'needs_render' or (pg.read_status = 'identity_mismatch' and pg.fetched_via = 'firecrawl' and exists (select 1 from pipeline.uni_adapters u where u.provider_id = pg.provider_id and coalesce(u.json_source, '') <> '') and not exists (select 1 from pipeline.page_link_repairs x where x.course_id = pg.course_id and x.reason like 'university adapter: page read again%')))
                    and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = pg.course_id and k.field = 'official_url'));
  insert into pipeline.page_link_repairs(course_id, provider_id, old_url, new_url, reason)
    select pg.course_id, pg.provider_id, pg.url, pg.url, 'university adapter: page read again (' || p_reason || ')'
    from pipeline.coverage_course_pages pg where pg.course_id = any (v_ids);
  update pipeline.coverage_course_pages pg set status = 'bound', read_status = 'needs_render', next_read_at = now(), leased_until = null where pg.course_id = any (v_ids);
  get diagnostics n = row_count;
  return n;
end $f$;
revoke all on function security.uni_adapter_requeue_v1(uuid, text) from public, anon, authenticated;
