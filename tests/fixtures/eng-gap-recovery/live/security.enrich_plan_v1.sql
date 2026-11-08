CREATE OR REPLACE FUNCTION security.enrich_plan_v1(p_provider uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p record; c jsonb := security.enrich_unit_costs_v1(); f jsonb := security.enrich_provider_fields_v1(p_provider); v_steps jsonb := '[]'::jsonb;
        v_courses int; v_site boolean; v_contact boolean; v_central timestamptz; v_url_missing int; v_onb record; v_ad record; v_items int; v_nopage int;
        v_sch int; v_sch_scan timestamptz; v_work jsonb; v_held jsonb := '[]'::jsonb; v_empty jsonb;
begin
  select pr.id, coalesce(pr.display_name, pr.canonical_name) name, security.coverage_country(pr.id) cc, nullif(btrim(pr.website), '') website,
         nullif(btrim(pr.phone), '') is not null or nullif(btrim(pr.email), '') is not null has_contact
    into p from catalogue.providers pr where pr.id = p_provider;
  if p.id is null then return null; end if;
  select count(*) into v_courses from catalogue.courses c2 where c2.provider_id = p_provider and c2.lifecycle_status = 'active';
  select s.searched_at into v_central from pipeline.provider_central_search s where s.provider_id = p_provider and s.state = 'done';
  -- 1 website, contacts and central pages
  if p.website is null or not p.has_contact or v_central is null or v_central < now() - interval '30 days' then  -- fixed: the central-page refresh interval (central_refresh_days) is 30
    v_steps := v_steps || jsonb_build_object('step', 'site', 'label', 'Website, contacts and central pages',
      'why', case when p.website is null then 'No website known' when v_central is null then 'Central pages (fees, English, calendar) never searched'
                  when v_central < now() - interval '30 days' then 'Central pages last searched ' || to_char(v_central, 'DD Mon YYYY') else 'No public phone or email' end,
      'fields', jsonb_build_array('p_website', 'p_contact', 'provider_tuition', 'english', 'intakes'), 'est_credits', c->'site_credits', 'est_usd', 0, 'group', 'other');
  end if;
  -- 2 course pages
  v_url_missing := coalesce((f->'official_url'->>'missing')::int, 0);
  if v_url_missing > 0 then
    v_steps := v_steps || jsonb_build_object('step', 'pages', 'label', 'Find course pages',
      'why', v_url_missing || ' of ' || v_courses || ' courses have no course page', 'fields', jsonb_build_array('official_url'),
      'est_credits', round(v_url_missing * (c->>'search_credits_per_course')::numeric, 0), 'est_usd', 0, 'group', 'course_search',
      'blocked', case when p.website is null then 'Needs a website first (step 1)' end);
  end if;
  -- 3 adapter (onboarding) and 4 admit
  select a.enabled, a.admit, coalesce(jsonb_array_length(to_jsonb(a.admit_fields)), 0) n into v_ad from pipeline.uni_adapters a where a.provider_id = p_provider;
  select o.status, o.stop_reason into v_onb from pipeline.provider_onboarding o where o.provider_id = p_provider order by o.created_at desc limit 1;
  if not coalesce(v_ad.admit, false) then
    if v_onb.status = 'waiting_admit' then
      v_steps := v_steps || jsonb_build_object('step', 'admit', 'label', 'Admit the adapter', 'why', 'The adapter passed; a person admits it on Layer 2/3 › Universities',
        'fields', jsonb_build_array('provider_tuition', 'english', 'intakes', 'duration'), 'est_credits', 0, 'est_usd', 0, 'group', 'none', 'person', true);
    else
      v_steps := v_steps || jsonb_build_object('step', 'adapter', 'label', 'Build the adapter (onboarding)',
        'why', case when v_onb.status is null then 'No adapter yet' when v_onb.status = 'stopped' then 'Onboarding stopped: ' || replace(coalesce(v_onb.stop_reason, 'unknown'), '_', ' ')
                    when v_onb.status in ('done', 'cancelled') then 'No admitting adapter' else 'Onboarding running: ' || v_onb.status end,
        'fields', jsonb_build_array('provider_tuition', 'english', 'intakes', 'duration', 'campus'), 'est_credits', c->'adapter_credits', 'est_usd', c->'adapter_usd', 'group', 'reads',
        'running', v_onb.status is not null and v_onb.status not in ('done', 'cancelled', 'stopped', 'waiting_admit'),
        'blocked', case when p.website is null then 'Needs a website first (step 1)' end);
    end if;
  end if;
  -- 5 fields Enrich fields fills
  select count(*) into v_items from (
    select 1 from catalogue.courses c3 cross join unnest(array['campus', 'duration', 'level', 'delivery', 'field_of_study', 'international']) x(fld)
     where c3.provider_id = p_provider and c3.lifecycle_status = 'active'
       and case x.fld when 'campus' then not exists (select 1 from catalogue.course_campuses k where k.course_id = c3.id)
                      when 'duration' then c3.duration_value is null when 'level' then c3.study_level_id is null
                      when 'delivery' then nullif(btrim(c3.delivery_mode), '') is null when 'field_of_study' then c3.primary_field_id is null
                      else c3.open_to_international is null end
       and not security.enrich_item_held_v1(c3.id, x.fld)) z;  -- held: tried on the same page already (until the page changes or gaps.recheck_days)
  if v_items > 0 then
    select count(*) into v_nopage from catalogue.courses c4 where c4.provider_id = p_provider and c4.lifecycle_status = 'active'
       and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c4.id and g.evidence_id is not null);
    v_steps := v_steps || jsonb_build_object('step', 'fields', 'label', 'Fill missing fields (stored pages, AI, new reads)',
      'why', v_items || ' missing values in duration, delivery, campus, level, field of study or international not yet tried on the current page',
      'fields', jsonb_build_array('duration', 'delivery', 'campus', 'campus_city', 'level', 'field_of_study', 'international'),
      'est_credits', least(v_nopage, v_items), 'est_usd', round(v_items * (c->>'enrich_usd_per_item')::numeric, 3), 'group', 'reads');
  end if;
  -- 6 scholarships
  select count(*) into v_sch from scholarship.scholarships s where s.provider_id = p_provider and s.lifecycle_status = 'active';
  select max(j.created_at) into v_sch_scan from pipeline.admin_jobs j where j.kind = 'scholarship_provider_scan' and j.scope = p_provider::text;
  if v_sch = 0 and (v_sch_scan is null or v_sch_scan < now() - interval '30 days') then  -- fixed: the scholarship cap period is 30 days
    -- CF-247 IQ-00066 (plans.step_needs_work_on): proposed only when the scan has eligible work now; otherwise listed as not proposed, with why
    v_work := case when security.pipeline_num_v1('plans.step_needs_work_on', 0) >= 1 then security.plan_step_work_v1(p_provider, 'scholarships') end;
    if not coalesce((v_work->>'work')::boolean, true) then
      v_held := v_held || jsonb_build_object('step', 'scholarships', 'label', 'Find and read scholarships', 'code', v_work->>'code', 'reason', v_work->>'reason');
    else
    v_steps := v_steps || jsonb_build_object('step', 'scholarships', 'label', 'Find and read scholarships',
      'why', case when v_sch_scan is null then 'No scholarships and never searched' else 'No scholarships; last searched ' || to_char(v_sch_scan, 'DD Mon YYYY') end,
      'fields', jsonb_build_array('p_scholarships'), 'est_credits', c->'scholarship_credits', 'est_usd', c->'scholarship_usd', 'group', 'scholarships',
      'blocked', case when p.website is null then 'Needs a website first (step 1)' end);
    end if;
  end if;
  -- CF-247 ops D (P0 mandate 15:37 §7, IQ-00066): repeated empty cycles. The automatic planner (no person behind the call) is not offered
  -- the steps of a university whose last plans.empty_cycles_max plans moved no data and nothing changed since (security.plan_empty_cycles_v1);
  -- they are listed under not_proposed with the reason. A person's Run now sees the steps and the notice.
  v_empty := security.plan_empty_cycles_v1(p_provider, (select coalesce(sum((v->>'missing')::int), 0) from jsonb_each(f) e(k, v)));
  if v_empty is not null and auth.uid() is null and jsonb_array_length(v_steps) > 0 then
    v_held := v_held || (select jsonb_agg(jsonb_build_object('step', x->>'step', 'label', x->>'label', 'code', 'repeated_empty', 'reason', v_empty->>'reason')) from jsonb_array_elements(v_steps) x);
    v_steps := '[]'::jsonb;
  end if;
  return jsonb_build_object('provider_id', p.id, 'name', p.name, 'country', p.cc, 'website', p.website,
    'courses', (select count(*) from catalogue.courses c5 where c5.provider_id = p_provider and c5.lifecycle_status = 'active'),
    'fields', f, 'missing', (select coalesce(sum((v->>'missing')::int), 0) from jsonb_each(f) e(k, v)),
    'steps', v_steps, 'not_proposed', v_held, 'empty_cycles', v_empty,
    'est_credits', (select coalesce(sum((x->>'est_credits')::numeric), 0) from jsonb_array_elements(v_steps) x),
    'est_usd', (select coalesce(round(sum((x->>'est_usd')::numeric), 3), 0) from jsonb_array_elements(v_steps) x),
    'unit_costs', c,
    'open_run', (select to_jsonb(r) - 'steps' || jsonb_build_object('steps', r.steps) from pipeline.enrich_plan_runs r where r.provider_id = p_provider and r.state in ('queued', 'running')));
end $function$
