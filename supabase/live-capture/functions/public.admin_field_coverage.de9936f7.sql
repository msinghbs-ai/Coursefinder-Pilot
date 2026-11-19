CREATE OR REPLACE FUNCTION public.admin_field_coverage(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_cc text := upper(nullif(btrim(coalesce(p_args->>'country', '')), ''));
        v_pid uuid := nullif(p_args->>'provider', '')::uuid; v_reason text := btrim(coalesce(p_args->>'reason', '')); v_f pipeline.field_crosscheck_findings%rowtype;
        v_job pipeline.admin_jobs%rowtype; v_ef text; v_actor text; v_id bigint; v_released int := 0; v_r jsonb; v_snap jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  if p_action = 'overview' then
    -- CF-247 W35: every country (no provider filter) answers from the cached snapshot; one university's figures are read live
    v_snap := case when v_pid is null then (select s.payload from pipeline.admin_read_snapshots s where s.key = 'field_coverage') end;
    select * into v_job from pipeline.admin_jobs j where j.kind = 'enrich_fields' and coalesce((j.args->>'standing')::boolean, false) order by j.created_at desc limit 1;
    return jsonb_build_object(
      'register', (select jsonb_agg(jsonb_build_object('field', r.field, 'level', r.level, 'label', r.label, 'group', r.grp, 'reader', r.reader, 'fills', r.fills,
                                                     'target_pct', r.target_pct, 'reason', r.reason, 'updated_at', r.updated_at) order by r.sort)
                     from pipeline.field_register r where r.active),
      -- every course field by country (the hourly coverage build); provider fields counted now
      'courses_by_country', case when v_snap is not null then (select coalesce(jsonb_agg(e), '[]'::jsonb) from jsonb_array_elements(v_snap->'courses_by_country') e where v_cc is null or e->>'country' = v_cc) else (select coalesce(jsonb_agg(jsonb_build_object('country', x.country_code, 'field', x.attribute, 'total', x.total, 'filled', x.filled,
                                                                        'in_queue', x.in_queue, 'not_stated', x.not_stated, 'in_review', x.in_review)), '[]'::jsonb)
                               from (select a.country_code, a.attribute, count(*) total, count(*) filter (where a.state = 'admitted') filled,
                                            count(*) filter (where a.state = 'in_queue') in_queue, count(*) filter (where a.state = 'not_on_page') not_stated,
                                            count(*) filter (where a.state in ('in_review', 'candidate', 'awaiting_l3')) in_review
                                       from pipeline.course_attribute_coverage a
                                      where (v_cc is null or a.country_code = v_cc) and (v_pid is null or a.provider_id = v_pid) group by 1, 2) x) end,
      'providers_by_country', case when v_snap is not null then (select coalesce(jsonb_agg(e), '[]'::jsonb) from jsonb_array_elements(v_snap->'providers_by_country') e where v_cc is null or e->>'country' = v_cc) else (select coalesce(jsonb_agg(jsonb_build_object('country', z.cc, 'field', z.field, 'total', z.total, 'filled', z.filled)), '[]'::jsonb)
                                 from (select p.cc, f.field, count(*) total, count(*) filter (where f.has) filled
                                         from (select p.*, security.coverage_country(p.id) cc from catalogue.providers p
                                                where coalesce(p.lifecycle_status, 'active') = 'active' and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
                                                  and (v_pid is null or p.id = v_pid)) p
                                         cross join lateral (values
                                           ('p_website', nullif(btrim(p.website), '') is not null),
                                           ('p_address', nullif(btrim(p.address_line1), '') is not null),
                                           ('p_campuses', exists (select 1 from catalogue.campuses k where k.provider_id = p.id)),
                                           ('p_type', p.provider_type_id is not null),
                                           ('p_international', p.enrols_international is not null),
                                           ('p_logo', nullif(btrim(p.logo_url), '') is not null or exists (select 1 from catalogue.provider_assets a where a.provider_id = p.id and a.asset_type = 'logo')),
                                           ('p_contact', nullif(btrim(p.phone), '') is not null or nullif(btrim(p.email), '') is not null),
                                           ('p_scholarships', exists (select 1 from scholarship.scholarships s where s.provider_id = p.id and s.lifecycle_status = 'active')),
                                           ('p_description', nullif(btrim(p.description), '') is not null)) f(field, has)
                                        where v_cc is null or p.cc = v_cc
                                        group by 1, 2) z) end,
      'computed_at', case when v_snap is not null then (v_snap->>'computed_at')::timestamptz else (select max(computed_at) from pipeline.course_attribute_coverage) end,
      'queue', jsonb_build_object(
        'enabled', (select enabled from pipeline.field_gap_queue_control where id = 1),
        'switched', (select jsonb_build_object('reason', reason, 'at', updated_at) from pipeline.field_gap_queue_control where id = 1),
        'schedule', (select j.schedule from cron.job j where j.jobname = 'field-gap-queue'),
        'last_tick', (select jsonb_build_object('at', d.start_time, 'status', d.status, 'message', left(d.return_message, 300)) from cron.job_run_details d join cron.job j on j.jobid = d.jobid
                       where j.jobname = 'field-gap-queue' order by d.start_time desc limit 1),
        'recheck_days', security.pipeline_num_v1('gaps.recheck_days', 60), 'items_per_run', security.pipeline_num_v1('gaps.items_per_run', 30000),
        'reads_per_day', security.pipeline_num_v1('gaps.scraper_reads_per_day', 200),
        'reads_today', (select count(*) from pipeline.field_enrich_items e join pipeline.admin_jobs j on j.id = e.job_id
                         where j.kind = 'enrich_fields' and coalesce((j.args->>'standing')::boolean, false) and 'scraper' = any (e.tried)
                           and e.updated_at >= (date_trunc('day', now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne')),
        'ai_spent_today_usd', case when v_snap is not null then (v_snap->>'ai_spent_today_usd')::numeric else (select x.spent from security.ai_spend_today_v1() x where x.use = 'enrich_fields') end,
        'ai_guard_usd', (select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'openrouter' and s.key = 'guard_enrich_fields'),
        'job', case when v_job.id is null then null else jsonb_build_object('id', v_job.id, 'state', v_job.state, 'title', v_job.title, 'progress', v_job.progress,
                     'created_at', v_job.created_at, 'finished_at', v_job.finished_at,
                     'by_field', (select jsonb_object_agg(field, s) from (select field, jsonb_object_agg(state, n) s from (
                                    select e.field, e.state, count(*) n from pipeline.field_enrich_items e where e.job_id = v_job.id group by 1, 2) a group by field) b)) end,
        'runs', (select count(*) from pipeline.admin_jobs j where j.kind = 'enrich_fields' and coalesce((j.args->>'standing')::boolean, false)),
        'filled_7d', (select count(*) from pipeline.field_enrich_items e join pipeline.admin_jobs j on j.id = e.job_id
                       where coalesce((j.args->>'standing')::boolean, false) and e.state = 'filled' and e.updated_at > now() - interval '7 days')),
      'crosscheck', (select coalesce(jsonb_agg(jsonb_build_object('field', field, 'state', state, 'n', n)), '[]'::jsonb)
                       from (select x.field, x.state, count(*) n from pipeline.field_crosscheck_findings x
                              where (v_cc is null or security.coverage_country(x.provider_id) = v_cc) and (v_pid is null or x.provider_id = v_pid) group by 1, 2) y),
      'can_decide', v_rank >= 4, 'can_manage', v_rank >= 6,
      'snapshot', case when v_snap is not null then security.admin_read_snapshot_meta_v1('field_coverage') end);
  elsif p_action = 'findings' then
    return jsonb_build_object('items', (select coalesce(jsonb_agg(r), '[]'::jsonb) from (
      select x.id, x.field, x.held_value, x.page_value, x.source, x.quote, x.state, x.found_at, x.course_id, c.canonical_title course, coalesce(p.display_name, p.canonical_name) provider,
             security.coverage_country(x.provider_id) country
        from pipeline.field_crosscheck_findings x join catalogue.courses c on c.id = x.course_id join catalogue.providers p on p.id = x.provider_id
       where x.state = coalesce(nullif(p_args->>'state', ''), 'open') and (nullif(p_args->>'field', '') is null or x.field = p_args->>'field')
         and (v_cc is null or security.coverage_country(x.provider_id) = v_cc) and (v_pid is null or x.provider_id = v_pid)
       order by coalesce(p.display_name, p.canonical_name), c.canonical_title, x.field
       limit least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200) offset greatest(coalesce((p_args->>'offset')::int, 0), 0)) r));
  elsif p_action = 'finding_decide' then
    if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    select * into v_f from pipeline.field_crosscheck_findings where id = (p_args->>'id')::bigint for update;
    if v_f.id is null or v_f.state <> 'open' then raise exception 'this difference is no longer open'; end if;
    if p_args->>'decision' = 'dismiss' then
      update pipeline.field_crosscheck_findings set state = 'dismissed', decided_at = now(), decided_by = auth.uid(), note = nullif(v_reason, '') where id = v_f.id;
    elsif p_args->>'decision' = 'accept' then
      perform set_config('cf.manual_edit', 'on', true);
      update catalogue.courses c set duration_value = case when v_f.field = 'duration' then (v_f.page_value->>'value')::numeric else c.duration_value end,
             duration_unit = case when v_f.field = 'duration' then v_f.page_value->>'unit' else c.duration_unit end,
             study_level_id = case when v_f.field = 'level' then (v_f.page_value->>'level_id')::uuid else c.study_level_id end,
             delivery_mode = case when v_f.field = 'delivery' then v_f.page_value->>'mode' else c.delivery_mode end, updated_at = now()
       where c.id = v_f.course_id;
      insert into pipeline.manual_locks(entity, entity_id, field, mode, set_by) values ('course', v_f.course_id, v_f.field, 'value', auth.uid())
      on conflict (entity, entity_id, field) do update set mode = 'value', set_by = excluded.set_by, set_at = now();
      update pipeline.field_crosscheck_findings set state = 'accepted', decided_at = now(), decided_by = auth.uid(), note = nullif(v_reason, '') where id = v_f.id;
      insert into search.refresh_requests(requested_by) values ('field cross-check accepted');
    else raise exception 'decision is dismiss or accept'; end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('field_crosscheck', p_args->>'decision', v_f.field || ' ' || v_f.course_id, jsonb_build_object('held', v_f.held_value, 'found', v_f.page_value, 'quote', v_f.quote, 'reason', v_reason), auth.uid());
    return jsonb_build_object('id', v_f.id, 'state', case when p_args->>'decision' = 'dismiss' then 'dismissed' else 'accepted' end);
  elsif p_action = 'queue_set' then
    if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    update pipeline.field_gap_queue_control set enabled = coalesce((p_args->>'enabled')::boolean, enabled), owner = auth.uid(), reason = v_reason, updated_at = now() where id = 1;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('field_gap_queue', case when (p_args->>'enabled')::boolean then 'on' else 'off' end, 'field-gap-queue', jsonb_build_object('reason', v_reason), auth.uid());
    return public.admin_field_coverage('overview', '{}'::jsonb);
  elsif p_action = 'target_set' then
    if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    update pipeline.field_register set target_pct = (p_args->>'target_pct')::numeric, reason = v_reason, updated_by = auth.uid(), updated_at = now()
     where field = p_args->>'field';
    if not found then raise exception 'unknown field'; end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('field_register', 'target', p_args->>'field', jsonb_build_object('target_pct', p_args->'target_pct', 'reason', v_reason), auth.uid());
    return public.admin_field_coverage('overview', '{}'::jsonb);
  elsif p_action = 'stalled' then
    -- CF-247 21 Oct 2026: fields below target that are not moving or are behind, with the cause and the action that resolves it
    return jsonb_build_object('items', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(security.field_stalled_v1()) x
                                         where (v_cc is null or x->>'country' = v_cc) and x->>'reason' is not null),
                              'days', security.pipeline_num_v1('stall.days', 7), 'min_points', security.pipeline_num_v1('stall.min_points', 1),
                              'gap_points', security.pipeline_num_v1('stall.country_gap_points', 30),
                              'history_from', (select min(snapshot_date) from pipeline.field_coverage_daily),
                              'can_fill', v_rank >= 4, 'can_release', v_rank >= 6);
  elsif p_action in ('fill_now', 'release_and_fill') then
    if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    if v_cc is null then raise exception 'choose a country'; end if;
    v_ef := case p_args->>'field' when 'campus_city' then 'campus' when 'p_address' then 'provider_address' else p_args->>'field' end;
    if not exists (select 1 from security.enrich_fields_v1() e where e.field = v_ef) then raise exception 'this field is not filled by Enrich fields'; end if;
    if p_action = 'release_and_fill' then
      if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
      if length(v_reason) < 4 then raise exception 'give a reason (kept with each released hold)'; end if;
      v_actor := coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text);
      for v_id in select f.id from pipeline.enrichment_flags f
                   where f.entity = 'course' and f.field = v_ef and f.reason_code = 'enrich_no_value' and f.state = 'counting'
                     and security.coverage_country(f.provider_id) = v_cc loop
        perform security.flag_release_v1(v_id, v_actor, 'person', 'Coverage › Stalled fields: ' || v_reason, jsonb_build_object('country', v_cc, 'field', v_ef), false);
        v_released := v_released + 1;
      end loop;
    end if;
    v_r := public.admin_enrich_fields('start', jsonb_build_object('countries', jsonb_build_array(v_cc), 'fields', jsonb_build_array(v_ef), 'ai', true, 'scraper', true,
             'reason', coalesce(nullif(v_reason, ''), 'Coverage › Stalled fields: Fill now')));
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('field_stalled', p_action, v_cc || '.' || v_ef, jsonb_build_object('released', v_released, 'task', v_r, 'reason', v_reason), auth.uid());
    return coalesce(v_r, '{}'::jsonb) || jsonb_build_object('released', v_released);
  elsif p_action = 'wording_list' then
    -- CF-247 21 Oct 2026: a university's own delivery wording (Platform Admin "Keep two, fix reader")
    return jsonb_build_object('items', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'provider_id', d.provider_id,
               'provider', coalesce((select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = d.provider_id), 'Every university'),
               'phrase', d.phrase, 'mode', d.mode, 'active', d.active, 'reason', d.reason, 'set_at', d.set_at) order by d.active desc, d.set_at desc), '[]'::jsonb)
             from pipeline.delivery_wording d), 'can_edit', v_rank >= 5);
  elsif p_action in ('wording_set', 'wording_off') then
    if v_rank < 5 then raise exception 'PIM Admin role or above required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept with the phrase)'; end if;
    if p_action = 'wording_off' then
      update pipeline.delivery_wording set active = false, reason = v_reason, set_by = auth.uid(), set_at = now() where id = (p_args->>'id')::bigint;
    else
      if length(btrim(coalesce(p_args->>'phrase', ''))) < 3 then raise exception 'give the phrase as the page writes it'; end if;
      insert into pipeline.delivery_wording(provider_id, phrase, mode, reason, set_by)
      values (nullif(p_args->>'provider_id', '')::uuid, btrim(p_args->>'phrase'), p_args->>'mode', v_reason, auth.uid())
      on conflict (provider_id, phrase) do update set mode = excluded.mode, active = true, reason = excluded.reason, set_by = excluded.set_by, set_at = now();
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('delivery_wording', p_action, coalesce(p_args->>'phrase', p_args->>'id'), jsonb_build_object('mode', p_args->>'mode', 'provider_id', p_args->>'provider_id', 'reason', v_reason), auth.uid());
    return public.admin_field_coverage('wording_list', '{}'::jsonb) || jsonb_build_object('crosscheck', security.field_crosscheck_v1());
  elsif p_action = 'run_now' then
    if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    return security.field_gap_queue_tick_v1();
  end if;
  raise exception 'unknown action %', p_action using errcode = '22023';
end $function$
