CREATE OR REPLACE FUNCTION security.scholarship_task_prepare_v1(p_kind text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_prov uuid[]; v_sch uuid[]; v_course uuid; v_before uuid[] := '{}'; v_pages int := 0; v_cands int := 0; v_title text; v_scope text; v_missing text;
begin
  if p_kind = 'scholarship_provider_scan' then
    v_prov := array(select distinct x::uuid from jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb)) x);
    if coalesce(cardinality(v_prov), 0) = 0 then raise exception 'choose at least one provider'; end if;
    if cardinality(v_prov) > 50 then raise exception 'at most 50 providers in one task'; end if;
    select string_agg(coalesce(p.display_name, p.canonical_name), ', ') into v_missing from catalogue.providers p
     where p.id = any (v_prov) and coalesce(nullif(btrim(p.website), ''), (select nullif(btrim(d.website), '') from pipeline.coverage_provider_discovery d where d.provider_id = p.id and d.status = 'mapped')) is null;
    if v_missing is not null then raise exception 'no website is known for %; add it on the provider first', v_missing; end if;
  elsif p_kind = 'scholarship_course_check' then
    v_course := (p_args->>'course_id')::uuid;
    select array[c.provider_id] into v_prov from catalogue.courses c where c.id = v_course;
    if v_prov is null then raise exception 'unknown course'; end if;
    v_before := array(select m.scholarship_id from scholarship.course_mappings m where m.course_id = v_course and m.mapping_state = 'mapped');
  elsif p_kind = 'scholarship_reread' then
    v_sch := array(select distinct x::uuid from jsonb_array_elements_text(coalesce(p_args->'scholarship_ids', '[]'::jsonb)) x);
    if coalesce(cardinality(v_sch), 0) = 0 then raise exception 'choose a scholarship'; end if;
    v_prov := array(select distinct s.provider_id from scholarship.scholarships s where s.id = any (v_sch));
    if not exists (select 1 from pipeline.scholarship_pages p where p.scholarship_id = any (v_sch)) then raise exception 'this scholarship has no provider page to read'; end if;
  else
    raise exception 'unknown scholarship task';
  end if;
  if exists (select 1 from security.provider_hidden_v1 h where h.provider_id = any (v_prov)) then
    raise exception 'a chosen provider is unpublished or archived; publish or restore it first';
  end if;
  if p_kind = 'scholarship_provider_scan' then
    insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status, attempts, updated_at)
    select p.id, coalesce(nullif(btrim(p.website), ''), (select nullif(btrim(d.website), '') from pipeline.coverage_provider_discovery d where d.provider_id = p.id and d.status = 'mapped')), 0, 'on_demand', 'pending', 0, now()
      from catalogue.providers p where p.id = any (v_prov)
    on conflict (provider_id) do update set status = 'pending', priority = 0, attempts = 0, leased_until = null, reason = 'on_demand', updated_at = now();
    update pipeline.scholarship_page_candidates c set next_read_at = now(), attempts = 0, leased_until = null, requested_at = now()
     where c.provider_id = any (v_prov) and c.admit_status is null and c.matched_scholarship_id is null and c.source <> 'register'
       and (c.read_status is null or c.read_status in ('blocked', 'fetch_failed', 'too_thin', 'not_html', 'robots_disallowed', 'scrape_failed', 'waiting_scraper', 'deferred'));
    get diagnostics v_cands = row_count;
  end if;
  update pipeline.scholarship_pages p set requested_at = now(), next_read_at = now(), attempts = 0, leased_until = null
    from scholarship.scholarships s
   where s.id = p.scholarship_id and s.lifecycle_status = 'active'
     and (case when v_sch is not null then s.id = any (v_sch) else s.provider_id = any (v_prov) end);
  get diagnostics v_pages = row_count;
  if v_pages = 0 and p_kind = 'scholarship_reread' then raise exception 'this scholarship is not active, so there is no page to read; restore it first'; end if;
  if v_pages = 0 and p_kind = 'scholarship_course_check' then raise exception 'this course''s provider has no active scholarship pages yet; use Find scholarships now on the provider'; end if;
  if v_sch is null then update pipeline.scholarship_listing_pages set next_read_at = now() where active and provider_id = any (v_prov); end if;
  v_title := case p_kind
    when 'scholarship_provider_scan' then 'Find scholarships now: ' || case when cardinality(v_prov) = 1 then (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = v_prov[1]) else cardinality(v_prov) || ' providers' end
    when 'scholarship_course_check' then 'Check scholarships for ' || (select coalesce(c.display_title, c.canonical_title) || coalesce(' (' || c.course_code || ')', '') from catalogue.courses c where c.id = v_course)
    else 'Read again now: ' || case when cardinality(v_sch) = 1 then (select s.name from scholarship.scholarships s where s.id = v_sch[1]) else cardinality(v_sch) || ' scholarships' end end;
  v_scope := case p_kind
    when 'scholarship_provider_scan' then case when cardinality(v_prov) = 1 then v_prov[1]::text else 'providers:' || md5(array_to_string(array(select x::text from unnest(v_prov) x order by 1), ',')) end
    when 'scholarship_course_check' then v_course::text
    else case when cardinality(v_sch) = 1 then v_sch[1]::text else 'scholarships:' || md5(array_to_string(array(select x::text from unnest(v_sch) x order by 1), ',')) end end;
  return jsonb_build_object('providers', to_jsonb(v_prov), 'scholarship_ids', to_jsonb(coalesce(v_sch, '{}'::uuid[])), 'course_id', v_course, 'before', to_jsonb(v_before),
                            'pages', v_pages, 'candidates', v_cands, 'title', v_title, 'scope', v_scope);
end $function$
