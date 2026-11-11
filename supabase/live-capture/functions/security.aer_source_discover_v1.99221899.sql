CREATE OR REPLACE FUNCTION security.aer_source_discover_v1(p_preview boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cap numeric := security.pipeline_num_v1('aer.source_discover_credits_per_day', 200); v_recheck int := security.pipeline_num_v1('aer.source_discover_recheck_days', 30)::int;
        v_tries int := security.pipeline_num_v1('aer.source_discover_max_tries', 3)::int; v_per numeric; v_used numeric; v_room int; v_settled int := 0; v_asked int := 0; r record; v_out text; v_cr numeric;
begin
  if security.pipeline_num_v1('aer.source_discover_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  -- (a) settle open requests from what the search recorded
  for r in select q.id, q.provider_id, q.requested_at, s.state, s.searched_at, s.requested_at s_req, s.evidence, s.found
             from pipeline.aer_source_discover_requests q left join pipeline.provider_central_search s on s.provider_id = q.provider_id
            where q.outcome is null loop
    v_out := case when exists (select 1 from pipeline.entry_matrix_sources m where m.provider_id = r.provider_id) then 'entry_source_found'
                  when r.searched_at is not null and r.searched_at >= r.requested_at then
                       case when exists (select 1 from pipeline.coverage_course_pages g where g.provider_id = r.provider_id and g.status = 'bound') then 'course_pages_found' else 'no_entry_page' end
                  when r.s_req is null and r.evidence ? 'refusal' then 'refused'
                  when r.state = 'failed' or (r.evidence ? 'error' and r.s_req is null) then 'failed'
                  else null end;
    if v_out is not null and not p_preview then
      select coalesce(sum(u.units), 0) into v_cr from pipeline.coverage_vendor_usage u
       where u.provider_id = r.provider_id and u.at >= r.requested_at and security.fc_purpose_group_v1(u.purpose) = 'central';
      update pipeline.aer_source_discover_requests set outcome = v_out, outcome_at = now(), credits = v_cr,
             detail = detail || jsonb_build_object('search_state', r.state, 'searched_at', r.searched_at, 'evidence', r.evidence,
                                                   'entry_suggestions', (select count(*) from jsonb_array_elements(coalesce(r.found, '[]'::jsonb)) e where e->>'kind' = 'entry_requirements'))
       where id = r.id;
      v_settled := v_settled + 1;
    end if;
  end loop;
  -- (b) credits the asked providers used in the last 24 hours, and the measured average a provider
  select coalesce(sum(u.units), 0) into v_used from pipeline.coverage_vendor_usage u
   where u.at > now() - make_interval(hours => 24) and security.fc_purpose_group_v1(u.purpose) = 'central' -- fixed: the daily limit counts the last 24 hours
     and exists (select 1 from pipeline.aer_source_discover_requests q where q.provider_id = u.provider_id and u.at >= q.requested_at);
  select coalesce(round(sum(units) / nullif(count(distinct provider_id), 0), 1), 4) into v_per from pipeline.coverage_vendor_usage where purpose = 'central_map';
  v_per := greatest(v_per, 1);
  -- requests still open are planned at the average too
  v_used := v_used + v_per * (select count(*) from pipeline.aer_source_discover_requests q where q.outcome is null
                                and not exists (select 1 from pipeline.coverage_vendor_usage u where u.provider_id = q.provider_id and u.at >= q.requested_at));
  v_room := greatest(0, floor((v_cap - v_used) / v_per))::int;
  -- (c) ask the central-page search for that many more providers with nothing stored
  for r in select n.provider_id from security.aer_no_source_route_v1() n
             join catalogue.providers p on p.id = n.provider_id
            where n.route = 'nothing_stored' and p.website ~* '^https?://' and not security.third_party_host_v1(p.website)
              and not exists (select 1 from pipeline.aer_source_discover_requests q where q.provider_id = n.provider_id
                                and (q.outcome is null or (q.outcome in ('no_entry_page', 'course_pages_found', 'failed') and q.outcome_at > now() - make_interval(days => v_recheck))
                                     or (q.outcome = 'refused' and q.outcome_at > now() - make_interval(hours => 24)))) -- fixed: a refusal is asked again after a day
              and (select count(*) from pipeline.aer_source_discover_requests q where q.provider_id = n.provider_id and q.outcome in ('no_entry_page', 'course_pages_found', 'failed')) < v_tries
            order by (select count(*) from catalogue.courses c where c.provider_id = n.provider_id and c.lifecycle_status = 'active') desc, n.provider_id
            limit v_room loop
    if not p_preview then
      insert into pipeline.provider_central_search(provider_id, state, requested_at, attempts, updated_at) values (r.provider_id, 'queued', now(), 0, now())
      on conflict (provider_id) do update set state = case when pipeline.provider_central_search.state = 'leased' and pipeline.provider_central_search.leased_until > now() then pipeline.provider_central_search.state else 'queued' end,
             requested_at = now(), attempts = 0, updated_at = now();
      insert into pipeline.aer_source_discover_requests(provider_id, detail) values (r.provider_id, jsonb_build_object('planned_credits', v_per, 'route', 'nothing_stored'));
    end if;
    v_asked := v_asked + 1;
  end loop;
  return jsonb_build_object('on', true, 'preview', p_preview, 'settled', v_settled, 'asked', v_asked, 'credits_used_24h_or_planned', v_used, 'credits_per_provider', v_per, 'cap', v_cap);
end $function$
