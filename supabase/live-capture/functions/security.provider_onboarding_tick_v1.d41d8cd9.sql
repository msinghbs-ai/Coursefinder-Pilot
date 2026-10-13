CREATE OR REPLACE FUNCTION security.provider_onboarding_tick_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s pipeline.provider_onboarding_settings%rowtype; o record; v_active int; v_n int := 0; v_err int := 0; v_started int := 0; v_b jsonb;
begin
  select * into s from pipeline.provider_onboarding_settings where id = 1;
  if not coalesce(s.enabled, false) then return jsonb_build_object('skipped', 'onboarding is switched off'); end if;
  -- v2.15.260 (keep moving): enough course pages read since it stopped for too few: carry on
  update pipeline.provider_onboarding ob set status = 'course_pages', stop_reason = null, step_started_at = now(), job_id = null, note = 'Enough course pages read now; carrying on.', updated_at = now()
   where ob.status = 'stopped' and ob.stop_reason = 'too_few_pages'
     and (select count(*) from pipeline.coverage_course_pages pg where pg.provider_id = ob.provider_id and pg.read_status = 'read')
         >= least(3, greatest((select count(*) from catalogue.courses c where c.provider_id = ob.provider_id and c.lifecycle_status = 'active'), 1));
  -- v2.15.260: the adapter AI allowance renewed: carry on (from its course pages, so the sample pages are captured again)
  v_b := security.adapter_builder_budget();
  if (v_b->>'used_usd')::numeric < (v_b->>'limit_usd')::numeric and (v_b->>'proposals')::int < (v_b->>'limit_proposals')::int then
    update pipeline.provider_onboarding ob set status = 'course_pages', stop_reason = null, step_started_at = now(), job_id = null, attempts = 0, note = 'The AI allowance renewed; carrying on.', updated_at = now()
     where ob.status = 'stopped' and ob.stop_reason = 'ai_allowance';
  end if;
  -- a missing website was entered: carry on
  update pipeline.provider_onboarding ob set status = 'website', stop_reason = null, step_started_at = now(), job_id = null, note = 'Website entered; carrying on.', updated_at = now()
    from catalogue.providers pv where pv.id = ob.provider_id and ob.status = 'stopped' and ob.stop_reason = 'no_website' and nullif(pv.website, '') is not null;
  -- v2.15.255: a university that needed a person and has since been admitted by hand is done
  -- v2.15.258: then its courses are enriched (stage 5) and its scholarships found, instead of finishing here
  update pipeline.provider_onboarding ob set status = 'scholarships', stop_reason = null, step_started_at = now(), job_id = null,
         result = (ob.result - 'enrich_from') || jsonb_build_object('phase', 'enrich', 'admitted_at', now()), note = 'Admitted by a person; its courses are enriched next.', updated_at = now()
   where ob.status = 'stopped' and ob.stop_reason in ('nothing_ready', 'approve_central')
     and exists (select 1 from pipeline.uni_adapters a where a.provider_id = ob.provider_id and a.enabled and coalesce(a.admit, false));
  -- v2.15.256: central pages read by the AI and decided by a person (at least one approved): done
  update pipeline.provider_onboarding ob set status = 'scholarships', stop_reason = null, step_started_at = now(), job_id = null,
         result = (ob.result - 'enrich_from') || jsonb_build_object('phase', 'enrich', 'admitted_at', now()), note = 'Central pages approved by a person; its courses are enriched next.', updated_at = now()
   where ob.status = 'stopped' and ob.stop_reason = 'approve_central'
     and not exists (select 1 from pipeline.provider_policy_proposals pp where pp.provider_id = ob.provider_id and pp.status = 'proposed')
     and exists (select 1 from pipeline.provider_policy_proposals pp where pp.provider_id = ob.provider_id and pp.status = 'approved' and pp.decided_at >= coalesce(ob.started_at, ob.created_at));
  -- v2.15.258: only the working stages count towards "at once"; Admit, Enrich and Admit scholarships wait
  select count(*) into v_active from pipeline.provider_onboarding
   where status in ('website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying')
      or (status = 'scholarships' and coalesce(result->>'phase', 'scholarship_search') = 'scholarship_search');
  for o in select id from pipeline.provider_onboarding where status = 'queued' order by priority desc, created_at limit greatest(coalesce(s.max_active, 0) - v_active, 0) loop
    update pipeline.provider_onboarding set status = 'website', started_at = now(), step_started_at = now(), note = 'Starting.', updated_at = now() where id = o.id;
    v_started := v_started + 1;
  end loop;
  for o in select ob.id, coalesce(ob.requested_by, s.run_as) run_as from pipeline.provider_onboarding ob
            where ob.status in ('website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying')
               or (ob.status = 'scholarships' and coalesce(ob.result->>'phase', 'scholarship_search') = 'scholarship_search')
               -- v2.15.258: the waiting stages (Admit, Enrich, Admit scholarships) are checked every 10 minutes, after the working ones
               or ((ob.status = 'waiting_admit' or (ob.status = 'scholarships' and ob.result->>'phase' in ('enrich', 'scholarship_admit'))) and ob.updated_at < now() - make_interval(mins => security.pipeline_num_v1('onboarding.waiting_check_minutes', 10)::int))
               or (ob.status = 'waiting_courses' and ob.updated_at < now() - make_interval(hours => security.pipeline_num_v1('onboarding.waiting_courses_check_hours', 1)::int))
            order by case when ob.status = 'waiting_admit' or ob.status = 'waiting_courses' or ob.result->>'phase' in ('enrich', 'scholarship_admit') then 1 else 0 end, ob.updated_at
            limit security.pipeline_num_v1('onboarding.universities_per_minute', 250)::int loop
    begin
      perform set_config('request.jwt.claims', jsonb_build_object('sub', o.run_as::text, 'role', 'authenticated')::text, true);
      perform security.provider_onboarding_step_v1(o.id);
      v_n := v_n + 1;
    exception when others then
      -- v2.15.260: a used-up AI allowance or a missing website is a plain reason that carries on by itself, not an unexpected error
      update pipeline.provider_onboarding set status = 'stopped',
             stop_reason = case when sqlerrm ilike '%proposals for today are used%' or sqlerrm ilike '%allowance%' then 'ai_allowance'
                                when sqlerrm ilike '%no website is recorded%' then 'no_website' else 'error' end,
             note = left(case when sqlerrm ilike '%proposals for today are used%' or sqlerrm ilike '%allowance%' then 'The adapter AI allowance for today is used; carries on by itself when it renews (midnight, Melbourne time). '
                              when sqlerrm ilike '%no website is recorded%' then 'No website is recorded; enter it in the Adapter builder (1.1) or Layer 4 › Websites to find, and onboarding carries on by itself. '
                              else '' end || 'Stopped: ' || sqlerrm, 500), updated_at = now() where id = o.id;
      v_err := v_err + 1;
    end;
    perform set_config('request.jwt.claims', '', true);
  end loop;
  return jsonb_build_object('started', v_started, 'advanced', v_n, 'stopped_by_error', v_err);
end $function$
