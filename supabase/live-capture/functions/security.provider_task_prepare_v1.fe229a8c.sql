CREATE OR REPLACE FUNCTION security.provider_task_prepare_v1(p_kind text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_name text; v_site text; v_ids uuid[]; v_n int := 0;
begin
  select coalesce(p.display_name, p.canonical_name), nullif(btrim(p.website), '') into v_name, v_site from catalogue.providers p where p.id = v_pid and p.lifecycle_status = 'active';
  if v_name is null then raise exception 'choose an active provider'; end if;
  if exists (select 1 from security.provider_hidden_v1 h where h.provider_id = v_pid) then raise exception 'this provider is unpublished or archived; publish or restore it first'; end if;
  if p_kind = 'provider_fill' then
    if v_site is null then
      insert into pipeline.coverage_provider_discovery(provider_id, status, requested_at, updated_at) values (v_pid, 'no_website', now(), now())
      on conflict (provider_id) do update set status = case when pipeline.coverage_provider_discovery.website is null then 'no_website' else pipeline.coverage_provider_discovery.status end,
             site_searched_at = null, leased_until = null, requested_at = now(), updated_at = now();
      -- a website already found and verified earlier is adopted straight away
      perform security.provider_website_adopt_v1(v_pid, d.website) from pipeline.coverage_provider_discovery d where d.provider_id = v_pid and d.site_source like 'search_verified_%' and d.website is not null;
      select nullif(btrim(p.website), '') into v_site from catalogue.providers p where p.id = v_pid;
    end if;
    if v_site is not null then
      insert into pipeline.provider_central_search(provider_id, state, requested_at) values (v_pid, 'queued', now())
      on conflict (provider_id) do update set state = 'queued', requested_at = now(), leased_until = null, attempts = 0, updated_at = now();
    end if;
    update pipeline.provider_contact_checks set checked_at = now() - interval '91 days', outcome = 'requested' where provider_id = v_pid and kind = 'public_general';
    return jsonb_build_object('provider_id', v_pid, 'had_website', v_site is not null, 'title', 'Fill in from website: ' || v_name, 'scope', v_pid::text);
  elsif p_kind = 'course_page_find' then
    if not exists (select 1 from pipeline.course_link_recipes x where x.provider_id = v_pid and x.active) then
      raise exception 'no website is recorded for this provider yet, so there is nowhere to search; use Fill in from website first';
    end if;
    v_ids := array(select c.id from catalogue.courses c where c.provider_id = v_pid and c.lifecycle_status = 'active'
                     and (case when jsonb_typeof(p_args->'course_ids') = 'array' and jsonb_array_length(p_args->'course_ids') > 0
                               then c.id = any (array(select x::uuid from jsonb_array_elements_text(p_args->'course_ids') x))
                               else not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id and g.read_status = 'read') end));
    if coalesce(cardinality(v_ids), 0) = 0 then raise exception 'every course of this provider already has a read page'; end if;
    if cardinality(v_ids) > 300 then raise exception 'at most 300 courses in one task'; end if;
    insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at, requested_at)
    select c.id, c.provider_id, case when c.course_code ~ '^[0-9]{6}[0-9A-Z]$' then 'cricos' else 'title' end, 'queued', now(), now()
      from catalogue.courses c where c.id = any (v_ids)
    on conflict (course_id) do update set state = 'queued', stage = excluded.stage, attempts = 0, cand_idx = 0, queued_at = now(), requested_at = now(), sent_at = null
     where pipeline.course_link_search.state not in ('sent');
    get diagnostics v_n = row_count;
    return jsonb_build_object('provider_id', v_pid, 'course_ids', to_jsonb(v_ids), 'queued', v_n,
                              'title', 'Find course pages: ' || v_name || ' (' || cardinality(v_ids) || ' course' || case when cardinality(v_ids) = 1 then '' else 's' end || ')',
                              'scope', v_pid::text || ':' || md5(array_to_string(array(select x::text from unnest(v_ids) x order by 1), ',')));
  end if;
  raise exception 'unknown provider task';
end $function$
