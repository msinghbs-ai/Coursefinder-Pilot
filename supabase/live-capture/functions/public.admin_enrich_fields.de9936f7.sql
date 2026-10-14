CREATE OR REPLACE FUNCTION public.admin_enrich_fields(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_cc text[]; v_pids uuid[]; v_fields text[]; v_job uuid; v_reason text; v_n int; v_title text;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  v_cc := array(select upper(x) from jsonb_array_elements_text(coalesce(p_args->'countries', '[]'::jsonb)) x);
  v_pids := array(select x::uuid from jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb)) x);
  v_fields := array(select x from jsonb_array_elements_text(coalesce(p_args->'fields', '[]'::jsonb)) x where x in (select f.field from security.enrich_fields_v1() f));
  if p_action = 'fields' then
    return jsonb_build_object('fields', (select jsonb_agg(jsonb_build_object('field', f.field, 'label', f.label, 'level', f.level, 'allowed', f.sources) order by f.sort) from security.enrich_fields_v1() f),
      'rules', (select coalesce(jsonb_agg(jsonb_build_object('country', r.country_code, 'field', r.field, 'sources', r.sources, 'reason', r.reason, 'updated_at', r.updated_at) order by r.country_code, r.field), '[]'::jsonb) from pipeline.field_source_rules r),
      'countries', (select jsonb_agg(c order by c) from unnest(security.catalogue_country_codes_v1()) c),
      'can_start', v_rank >= 4, 'can_manage', v_rank >= 6);
  elsif p_action = 'preview' then
    if coalesce(array_length(v_fields, 1), 0) = 0 then raise exception 'choose at least one field'; end if;
    return (with scope as (
              select c.id, c.provider_id, c.study_level_id, c.primary_field_id, c.duration_value, c.delivery_mode, c.open_to_international, k.iso_alpha2::text cc
                from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id
               where c.lifecycle_status = 'active' and (cardinality(v_cc) = 0 or k.iso_alpha2::text = any (v_cc)) and (cardinality(v_pids) = 0 or c.provider_id = any (v_pids))),
            f as (select x field from unnest(v_fields) x)
            select jsonb_build_object('courses', (select count(*) from scope), 'universities', (select count(distinct provider_id) from scope),
              'fields', jsonb_agg(jsonb_build_object('field', f.field,
                'missing', case f.field when 'campus' then (select count(*) from scope s where not exists (select 1 from catalogue.course_campuses x where x.course_id = s.id))
                                        when 'duration' then (select count(*) from scope s where s.duration_value is null)
                                        when 'level' then (select count(*) from scope s where s.study_level_id is null)
                                        when 'delivery' then (select count(*) from scope s where nullif(btrim(s.delivery_mode), '') is null)
                                        when 'field_of_study' then (select count(*) from scope s where s.primary_field_id is null)
                                        when 'international' then (select count(*) from scope s where s.open_to_international is null)
                                        when 'provider_address' then (select count(*) from catalogue.providers p where p.id in (select provider_id from scope) and nullif(btrim(p.address_line1), '') is null) end,
                'stored_page', case when f.field = 'provider_address' then (select count(distinct s2.provider_id) from pipeline.evidence_artifacts e join pipeline.sources s2 on s2.id = e.source_id
                                                                             where s2.provider_id in (select provider_id from scope) and e.evidence_type in ('provider_contact_html_snapshot', 'enrich_home_page'))
                                    else (select count(*) from scope s join pipeline.coverage_course_pages g on g.course_id = s.id where g.evidence_id is not null) end,
                'adapter_value', case f.field when 'campus' then (select count(*) from scope s where exists (select 1 from pipeline.uni_adapter_results r where r.course_id = s.id and coalesce(r.fields->'extra'->>'campus', r.fields->'extra'->>'location') is not null))
                                              when 'duration' then (select count(*) from scope s where s.duration_value is null and exists (select 1 from pipeline.uni_adapter_results r where r.course_id = s.id and r.fields->'extra'->>'duration' is not null))
                                              when 'delivery' then (select count(*) from scope s where nullif(btrim(s.delivery_mode), '') is null and exists (select 1 from pipeline.uni_adapter_results r where r.course_id = s.id and r.fields->'extra'->>'mode' is not null))
                                              when 'level' then (select count(*) from scope s where s.study_level_id is null and exists (select 1 from pipeline.uni_adapter_results r where r.course_id = s.id and r.fields->'extra'->>'study_level' is not null))
                                              else null end) order by f.field))
              from f);
  elsif p_action = 'start' then
    if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    v_reason := btrim(coalesce(p_args->>'reason', ''));
    if length(v_reason) < 4 then raise exception 'give a reason (it is kept with the task)'; end if;
    if coalesce(array_length(v_fields, 1), 0) = 0 then raise exception 'choose at least one field'; end if;
    if cardinality(v_cc) = 0 and cardinality(v_pids) = 0 then raise exception 'choose countries or universities'; end if;
    v_title := 'Enrich ' || array_to_string(v_fields, ', ') || ' · ' || case when cardinality(v_pids) > 0 then cardinality(v_pids) || ' universit' || case when cardinality(v_pids) = 1 then 'y' else 'ies' end else array_to_string(v_cc, ', ') end;
    insert into pipeline.admin_jobs(kind, lane, state, title, args, progress, requested_by, reason, scope)
    values ('enrich_fields', 'enrich', 'queued', left(v_title, 200),
            jsonb_build_object('countries', to_jsonb(v_cc), 'provider_ids', to_jsonb(v_pids), 'fields', to_jsonb(v_fields),
                               'ai', coalesce((p_args->>'ai')::boolean, true), 'scraper', coalesce((p_args->>'scraper')::boolean, false)),
            jsonb_build_object('done', 0, 'total', 0), auth.uid(), v_reason, coalesce(nullif(array_to_string(v_cc, ', '), ''), cardinality(v_pids) || ' universities'))
    returning id into v_job;
    -- one item per course and missing field; one per university for its address and its campus list
    insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field)
    select v_job, c.provider_id, c.id, f.x
      from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id
      cross join unnest(v_fields) f(x)
     where c.lifecycle_status = 'active' and f.x <> 'provider_address'
       and (cardinality(v_cc) = 0 or k.iso_alpha2::text = any (v_cc)) and (cardinality(v_pids) = 0 or c.provider_id = any (v_pids))
       and case f.x when 'campus' then not exists (select 1 from catalogue.course_campuses x where x.course_id = c.id)
                    when 'duration' then c.duration_value is null when 'level' then c.study_level_id is null
                    when 'delivery' then nullif(btrim(c.delivery_mode), '') is null when 'field_of_study' then c.primary_field_id is null
                    when 'international' then c.open_to_international is null else false end
    on conflict do nothing;
    insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state)
    select distinct v_job, e.provider_id, null::uuid, 'campus_list', 'waiting' from pipeline.field_enrich_items e where e.job_id = v_job and e.field = 'campus'
    on conflict do nothing;
    if 'provider_address' = any (v_fields) then
      insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field)
      select v_job, p.id, null::uuid, 'provider_address'
        from catalogue.providers p join ref.countries k on k.id = p.country_id
       where nullif(btrim(p.address_line1), '') is null and coalesce(p.lifecycle_status, 'active') = 'active'
         and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
         and (cardinality(v_cc) = 0 or k.iso_alpha2::text = any (v_cc)) and (cardinality(v_pids) = 0 or p.id = any (v_pids))
      on conflict do nothing;
    end if;
    select count(*) into v_n from pipeline.field_enrich_items where job_id = v_job;
    update pipeline.admin_jobs set progress = jsonb_build_object('done', 0, 'total', v_n) where id = v_job;
    insert into pipeline.admin_job_events(job_id, note) values (v_job, v_n || ' item(s) to settle');
    return jsonb_build_object('job_id', v_job, 'items', v_n);
  elsif p_action = 'rule_set' then
    if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
    v_reason := btrim(coalesce(p_args->>'reason', ''));
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    if not exists (select 1 from security.enrich_fields_v1() f where f.field = p_args->>'field') then raise exception 'unknown field'; end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(p_args->'sources', '[]'::jsonb)) s
                where s not in (select unnest(f.sources) from security.enrich_fields_v1() f where f.field = p_args->>'field')) then
      raise exception 'a source that cannot fill this field';
    end if;
    insert into pipeline.field_source_rules(country_code, field, sources, reason, updated_by, updated_at)
    values (upper(coalesce(nullif(p_args->>'country', ''), 'ALL')), p_args->>'field', array(select jsonb_array_elements_text(p_args->'sources')), v_reason, auth.uid(), now())
    on conflict (country_code, field) do update set sources = excluded.sources, reason = excluded.reason, updated_by = excluded.updated_by, updated_at = now();
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('field_sources', 'set', upper(coalesce(nullif(p_args->>'country', ''), 'ALL')) || '.' || (p_args->>'field'), jsonb_build_object('sources', p_args->'sources', 'reason', v_reason), auth.uid());
    return public.admin_enrich_fields('fields', '{}'::jsonb);
  elsif p_action = 'jobs' then
    return (select jsonb_build_object('jobs', coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'title', j.title, 'state', j.state, 'progress', j.progress, 'result', j.result, 'reason', j.reason,
                     'args', j.args, 'created_at', j.created_at, 'finished_at', j.finished_at) order by j.created_at desc), '[]'::jsonb))
              from (select * from pipeline.admin_jobs where kind = 'enrich_fields' order by created_at desc limit 20) j);
  elsif p_action = 'items' then
    return (select jsonb_build_object('items', coalesce(jsonb_agg(x order by x->>'id' desc), '[]'::jsonb)) from (
      select jsonb_build_object('id', e.id, 'field', e.field, 'state', e.state, 'source', e.source, 'value', e.value, 'quote', e.quote, 'reason', e.reason,
               'provider', coalesce(p.display_name, p.canonical_name), 'course', c.canonical_title, 'course_id', e.course_id, 'provider_id', e.provider_id) x
        from pipeline.field_enrich_items e join catalogue.providers p on p.id = e.provider_id left join catalogue.courses c on c.id = e.course_id
       where e.job_id = (p_args->>'job_id')::uuid and (nullif(p_args->>'field', '') is null or e.field = p_args->>'field')
         and (nullif(p_args->>'state', '') is null or e.state = p_args->>'state')
       order by e.id desc limit least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200)) z);
  end if;
  raise exception 'unknown action %', p_action using errcode = '22023';
end $function$
