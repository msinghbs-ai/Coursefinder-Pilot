CREATE OR REPLACE FUNCTION security.provider_onboarding_tick_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s pipeline.provider_onboarding_settings%rowtype; o record; v_active int; v_n int := 0; v_err int := 0; v_started int := 0;
begin
  select * into s from pipeline.provider_onboarding_settings where id = 1;
  if not coalesce(s.enabled, false) then return jsonb_build_object('skipped', 'onboarding is switched off'); end if;
  -- a missing website was entered: carry on
  update pipeline.provider_onboarding ob set status = 'website', stop_reason = null, step_started_at = now(), job_id = null, note = 'Website entered; carrying on.', updated_at = now()
    from catalogue.providers pv where pv.id = ob.provider_id and ob.status = 'stopped' and ob.stop_reason = 'no_website' and nullif(pv.website, '') is not null;
  -- v2.15.255: a university that needed a person and has since been admitted by hand is done
  update pipeline.provider_onboarding ob set status = 'done', stop_reason = null, finished_at = now(), note = 'Admitted by a person; onboarding complete.', updated_at = now()
   where ob.status = 'stopped' and ob.stop_reason in ('nothing_ready', 'approve_central')
     and exists (select 1 from pipeline.uni_adapters a where a.provider_id = ob.provider_id and a.enabled and coalesce(a.admit, false));
  -- v2.15.256: central pages read by the AI and decided by a person (at least one approved): done
  update pipeline.provider_onboarding ob set status = 'done', stop_reason = null, finished_at = now(), note = 'Central pages approved by a person; onboarding complete.', updated_at = now()
   where ob.status = 'stopped' and ob.stop_reason = 'approve_central'
     and not exists (select 1 from pipeline.provider_policy_proposals pp where pp.provider_id = ob.provider_id and pp.status = 'proposed')
     and exists (select 1 from pipeline.provider_policy_proposals pp where pp.provider_id = ob.provider_id and pp.status = 'approved' and pp.decided_at >= coalesce(ob.started_at, ob.created_at));
  select count(*) into v_active from pipeline.provider_onboarding where status in ('website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying', 'scholarships');
  for o in select id from pipeline.provider_onboarding where status = 'queued' order by priority desc, created_at limit greatest(coalesce(s.max_active, 0) - v_active, 0) loop
    update pipeline.provider_onboarding set status = 'website', started_at = now(), step_started_at = now(), note = 'Starting.', updated_at = now() where id = o.id;
    v_started := v_started + 1;
  end loop;
  for o in select ob.id, coalesce(ob.requested_by, s.run_as) run_as from pipeline.provider_onboarding ob
            where ob.status in ('website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying', 'scholarships', 'waiting_admit')
               or (ob.status = 'waiting_courses' and ob.updated_at < now() - interval '1 hour')
            order by ob.updated_at limit 120 loop
    begin
      perform set_config('request.jwt.claims', jsonb_build_object('sub', o.run_as::text, 'role', 'authenticated')::text, true);
      perform security.provider_onboarding_step_v1(o.id);
      v_n := v_n + 1;
    exception when others then
      update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'error', note = left('Stopped: ' || sqlerrm, 500), updated_at = now() where id = o.id;
      v_err := v_err + 1;
    end;
    perform set_config('request.jwt.claims', '', true);
  end loop;
  return jsonb_build_object('started', v_started, 'advanced', v_n, 'stopped_by_error', v_err);
end $function$
