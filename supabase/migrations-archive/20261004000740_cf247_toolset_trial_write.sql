-- CF-247 Decision 252: start or stop a trial run (Platform Admin, with a reason; logged).
create or replace function public.admin_toolset_trial_write(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', ''));
        v_toolset text := p_args->>'toolset'; v_purpose text := p_args->>'purpose'; v_settings jsonb; v_countries text[]; v_n int;
        v_run uuid; v_cc text; v_added int := 0; v_r pipeline.toolset_trial_runs%rowtype;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'start' then
    if not ((v_toolset = 'serper' and v_purpose in ('find_course_page', 'find_provider_site')) or (v_toolset = 'scrapingbee' and v_purpose = 'render_page')) then
      raise exception 'this toolset does not run that trial'; end if;
    if not exists (select 1 from pipeline.layer2_acquisition_providers p where p.provider_key = v_toolset and p.vault_secret_id is not null) then
      raise exception 'save the % key on Platform settings › Environment & integrations first', v_toolset; end if;
    if exists (select 1 from pipeline.toolset_trial_runs r where r.toolset_key = v_toolset and r.status in ('ready', 'running', 'paused_time_limit')) then
      raise exception 'a % trial is still open; finish or stop it first', v_toolset; end if;
    select coalesce(jsonb_object_agg(s.key, s.value), '{}'::jsonb) into v_settings from pipeline.platform_toolset_settings s where s.toolset_key = v_toolset;
    select array_agg(x) into v_countries from jsonb_array_elements_text(v_settings->'trial_countries') x;
    v_n := (v_settings->>'trial_sample_per_country')::int;
    insert into pipeline.toolset_trial_runs(toolset_key, purpose, countries, settings, reason, requested_by)
      values (v_toolset, v_purpose, coalesce(v_countries, '{}'), v_settings, v_reason, auth.uid()) returning id into v_run;
    foreach v_cc in array coalesce(v_countries, '{}') loop
      insert into pipeline.toolset_trial_items(run_id, country, subject_key, course_id, provider_id, input)
      select v_run, v_cc, b.subject_key, b.course_id, b.provider_id, b.input
      from security.toolset_trial_backlog(v_purpose, v_cc) b
      where not exists (select 1 from pipeline.toolset_trial_items i join pipeline.toolset_trial_runs r on r.id = i.run_id
                        where i.subject_key = b.subject_key and r.purpose = v_purpose and i.status = 'done')
      order by md5(b.subject_key || v_run::text) limit v_n;
      get diagnostics v_n = row_count; v_added := v_added + v_n; v_n := (v_settings->>'trial_sample_per_country')::int;
    end loop;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'trial_start', v_toolset || ':' || v_purpose, jsonb_build_object('run_id', v_run, 'cases', v_added, 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'run_id', v_run, 'cases', v_added);
  elsif p_action = 'stop' then
    select * into v_r from pipeline.toolset_trial_runs where id = (p_args->>'run_id')::uuid;
    if v_r.id is null then raise exception 'unknown run'; end if;
    update pipeline.toolset_trial_runs set status = 'stopped', status_note = v_reason, updated_at = now(), finished_at = now() where id = v_r.id and status in ('ready', 'running', 'paused_time_limit');
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'trial_stop', v_r.id::text, jsonb_build_object('reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown action %', p_action;
end $f$;
revoke all on function public.admin_toolset_trial_write(text, jsonb) from public, anon;
grant execute on function public.admin_toolset_trial_write(text, jsonb) to authenticated;
