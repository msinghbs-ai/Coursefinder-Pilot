-- CF-247 Decision 267 follow-up 3 (18 Oct 2026, before the second Build adapter wave). Platform Admin 17:20 "Proceed and always
-- consolidate next steps".
-- Found: Te Wananga o Raukawa stayed Ready for duration (23 values) after wave 1 because Enrichment took the adapter's value from
-- pipeline.uni_adapter_results (the Apply history), which held no duration for those courses, while the current page reading
-- (pipeline.coverage_course_pages.candidates) has "1 Year" for all 23. Those 23 had also been held as "no value" after an earlier try, so
-- the task did not queue them again.
-- 1 security.enrich_fields_slice_v1: the adapter source reads the current page reading first and the Apply history for what it lacks.
--   One line of the live definition is replaced (checked by md5 before and by content after); nothing else in it changes.
-- 2 public.admin_adapter_build (admit): before an Enrichment task starts, "no value" holds are released for that university's active
--   courses whose page reading now gives a value for the field (new input), with the reason. Other holds stay.
-- Replaces: security.enrich_fields_slice_v1 (adapter value from the Apply history only); public.admin_adapter_build (holds released at admit)
-- Retires: nothing
-- Nothing dropped or deleted. The consumer API is not touched (checked at the end).

do $guard$ begin
  if md5(pg_get_functiondef('public.admin_adapter_build(text,jsonb)'::regprocedure)) <> '3428eef302a7086bb045ddc683ca41ba' then
    raise exception 'public.admin_adapter_build is not the definition this change replaces';
  end if;
end $guard$;

do $slice$
declare d text := pg_get_functiondef('security.enrich_fields_slice_v1(uuid,integer)'::regprocedure);
  o text := $o$        select r.fields->'extra' into v_x from pipeline.uni_adapter_results r where r.course_id = it.course_id order by r.at desc limit 1;$o$;
  n text := $n$        -- 18 Oct 2026 (Decision 267 follow-up 3): the current page reading first, the Apply history for what it lacks
        select coalesce((select r.fields->'extra' from pipeline.uni_adapter_results r where r.course_id = it.course_id order by r.at desc limit 1), '{}'::jsonb)
               || coalesce((select g.candidates->'adapter_extra' from pipeline.coverage_course_pages g
                             where g.course_id = it.course_id and g.read_status = 'read' and g.identity_basis is not null), '{}'::jsonb)
          into v_x;$n$;
begin
  if md5(d) <> '03cc5526a082f59867a8313cdefa04fd' then raise exception 'security.enrich_fields_slice_v1 is not the definition this change replaces'; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'the line to replace is not found exactly once'; end if;
  execute replace(d, o, n);
  if position('the current page reading first, the Apply history for what it lacks' in pg_get_functiondef('security.enrich_fields_slice_v1(uuid,integer)'::regprocedure)) = 0 then
    raise exception 'post-check: slice not replaced';
  end if;
end $slice$;

create or replace function public.admin_adapter_build(p_action text, p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', ''));
  v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_pids uuid[]; v_cc text := upper(nullif(btrim(p_args->>'country'), ''));
  v_q text := nullif(btrim(p_args->>'query'), ''); v_stage text := nullif(btrim(p_args->>'stage'), ''); v_wave text := nullif(btrim(p_args->>'wave'), '');
  v_limit int := least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200);  -- fixed: page size bounds
  v_offset int := greatest(coalesce((p_args->>'offset')::int, 0), 0);
  r jsonb; v_fields text[]; v_adapter text[]; v_enrich text[]; v_done jsonb := '[]'::jsonb; v_job jsonb; v_m int; v_open uuid[]; v_stopped uuid[]; v_new uuid[]; p uuid; v_item jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  v_pids := coalesce(array(select x::uuid from jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb)) x), '{}');
  if v_pid is not null then v_pids := array_append(v_pids, v_pid); end if;

  if p_action in ('list', 'waves') then
    return (with base as (
      select pr.id provider_id, coalesce(pr.display_name, pr.canonical_name) name, k.iso_alpha2::text country,
             (select count(*) from catalogue.courses c where c.provider_id = pr.id and c.lifecycle_status = 'active') courses,
             b.pages_read, b.ready, b.review, b.not_ready, b.adds, b.checked_at, b.wave, b.readiness->'ready' ready_fields,
             u.enabled adapter_on, coalesce(u.admit, false) and cardinality(coalesce(u.admit_fields, '{}')) > 0 admitting,
             o.status onboarding, o.stop_reason, o.note onboarding_note,
             case when o.status is not null and o.status not in ('done', 'cancelled', 'stopped') then 'building'
                  when coalesce(u.admit, false) and cardinality(coalesce(u.admit_fields, '{}')) > 0 then 'admitted'
                  when u.enabled then 'tested'
                  when o.status = 'stopped' and o.stop_reason in ('too_few_pages', 'no_website') then 'needs_pages'
                  when o.status = 'stopped' then 'stopped'
                  else 'no_adapter' end stage
        from catalogue.providers pr
        join ref.countries k on k.id = pr.country_id
        left join pipeline.uni_adapters u on u.provider_id = pr.id
        left join pipeline.adapter_builds b on b.provider_id = pr.id
        left join lateral (select * from pipeline.provider_onboarding o where o.provider_id = pr.id order by o.created_at desc limit 1) o on true
       where coalesce(pr.lifecycle_status, 'active') = 'active'
         and k.iso_alpha2::text = any (security.catalogue_country_codes_v1())
         and exists (select 1 from catalogue.courses c where c.provider_id = pr.id and c.lifecycle_status = 'active')
         and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = pr.id)
         and (v_cc is null or k.iso_alpha2::text = v_cc)
         and (v_q is null or pr.canonical_name ilike '%' || v_q || '%' or coalesce(pr.display_name, '') ilike '%' || v_q || '%')
         and (v_wave is null or b.wave = v_wave)),
      f as (select * from base where v_stage is null or stage = v_stage)
      select case when p_action = 'waves' then
        jsonb_build_object('waves', coalesce((select jsonb_agg(jsonb_build_object('wave', w.wave, 'universities', w.n, 'courses', w.courses, 'by_stage', w.by_stage, 'ready', w.ready, 'review', w.review, 'not_ready', w.not_ready, 'adds', w.adds) order by w.wave)
                    from (select wave, count(*) n, sum(courses) courses, sum(ready) ready, sum(review) review, sum(not_ready) not_ready, sum(adds) adds,
                                 (select jsonb_object_agg(s.stage, s.n) from (select stage, count(*) n from base b2 where b2.wave = b1.wave group by stage) s) by_stage
                            from base b1 where wave is not null group by wave) w), '[]'::jsonb))
      else jsonb_build_object(
        'summary', (select jsonb_build_object('universities', count(*), 'courses', sum(courses), 'by_stage', (select jsonb_object_agg(s.stage, s.n) from (select stage, count(*) n from base group by stage) s),
                                              'ready', sum(ready), 'review', sum(review), 'not_ready', sum(not_ready), 'adds', sum(adds)) from base),
        'total', (select count(*) from f), 'limit', v_limit, 'offset', v_offset,
        'items', coalesce((select jsonb_agg(to_jsonb(z))
                             from (select * from f order by case stage when 'tested' then 1 when 'building' then 2 when 'needs_pages' then 3 when 'stopped' then 4 when 'no_adapter' then 5 else 6 end,
                                                          adds desc nulls last, courses desc, name limit v_limit offset v_offset) z), '[]'::jsonb),
        'can_build', v_rank >= 5, 'can_admit', v_rank >= 6) end
      from (select 1) one);

  elsif p_action = 'read' then
    if v_pid is null then raise exception 'choose a university'; end if;
    r := case when v_rank >= 5 then security.adapter_build_store_v1(v_pid) else security.adapter_build_fields_v1(v_pid) end;
    return r || jsonb_build_object(
      'university', (select jsonb_build_object('name', coalesce(pr.display_name, pr.canonical_name), 'website', pr.website, 'country', k.iso_alpha2) from catalogue.providers pr join ref.countries k on k.id = pr.country_id where pr.id = v_pid),
      'courses', (select count(*) from catalogue.courses c where c.provider_id = v_pid and c.lifecycle_status = 'active'),
      'pages', (select jsonb_build_object('bound', count(*), 'read', count(*) filter (where read_status = 'read' and identity_basis is not null),
                                          'other_course', count(*) filter (where read_status = 'identity_mismatch'), 'unreadable', count(*) filter (where read_status in ('fetch_failed', 'blocked', 'refused_host', 'robots_disallowed', 'needs_render', 'too_thin')))
                  from pipeline.coverage_course_pages where provider_id = v_pid),
      'links_fixed', (select count(*) from pipeline.admin_control_events e where e.action = 'rebind' and e.area = 'coverage'
                         and (e.detail->>'course_id')::uuid in (select c.id from catalogue.courses c where c.provider_id = v_pid)),
      'adapter', (select jsonb_build_object('enabled', u.enabled, 'admit', u.admit, 'admit_fields', u.admit_fields, 'updated_at', u.updated_at, 'patterns', (select jsonb_agg(k) from jsonb_object_keys(coalesce(u.patterns, '{}'::jsonb)) k)) from pipeline.uni_adapters u where u.provider_id = v_pid),
      'build', (select jsonb_build_object('status', o.status, 'stage', security.provider_onboarding_stage_v1(o.status, o.stop_reason, o.result), 'stop_reason', o.stop_reason, 'note', o.note,
                                          'started_at', o.started_at, 'finished_at', o.finished_at, 'updated_at', o.updated_at)
                  from pipeline.provider_onboarding o where o.provider_id = v_pid order by o.created_at desc limit 1),
      'ai_cost_usd', (select round(coalesce(sum(d.cost_usd), 0), 3) from pipeline.uni_adapter_drafts d where d.provider_id = v_pid),
      'wave', (select wave from pipeline.adapter_builds where provider_id = v_pid),
      'admitted', (select admitted from pipeline.adapter_builds where provider_id = v_pid),
      'can_build', v_rank >= 5, 'can_admit', v_rank >= 6);

  elsif p_action = 'build' then
    if v_rank < 5 then raise exception 'PIM Operator or Platform Admin required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept with the build)'; end if;
    if cardinality(v_pids) = 0 then raise exception 'choose universities'; end if;
    v_open := array(select distinct o.provider_id from pipeline.provider_onboarding o where o.provider_id = any (v_pids) and o.status not in ('done', 'cancelled', 'stopped'));
    v_stopped := array(select o.id from (select distinct on (o.provider_id) o.* from pipeline.provider_onboarding o where o.provider_id = any (v_pids) order by o.provider_id, o.created_at desc) o
                        where o.status = 'stopped');
    v_new := array(select i from unnest(v_pids) i where i <> all (v_open)
                     and not exists (select 1 from pipeline.provider_onboarding o where o.provider_id = i and o.status = 'stopped'
                                       and o.created_at = (select max(o2.created_at) from pipeline.provider_onboarding o2 where o2.provider_id = i)));
    if cardinality(v_stopped) > 0 then perform public.admin_provider_onboarding('retry', jsonb_build_object('ids', to_jsonb(v_stopped), 'reason', 'Build adapter: ' || v_reason)); end if;
    if cardinality(v_new) > 0 then perform public.admin_provider_onboarding('start', jsonb_build_object('provider_ids', to_jsonb(v_new), 'reason', 'Build adapter: ' || v_reason)); end if;
    if v_wave is not null then
      insert into pipeline.adapter_builds(provider_id, wave) select i, v_wave from unnest(v_pids) i
      on conflict (provider_id) do update set wave = excluded.wave, updated_at = now();
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('adapters', 'build', cardinality(v_pids) || ' universities', jsonb_build_object('decision', 267, 'reason', v_reason, 'wave', v_wave, 'started', cardinality(v_new), 'retried', cardinality(v_stopped), 'already_building', cardinality(v_open), 'provider_ids', to_jsonb(v_pids)), auth.uid());
    return jsonb_build_object('started', cardinality(v_new), 'retried', cardinality(v_stopped), 'already_building', cardinality(v_open));

  elsif p_action = 'set_wave' then
    if v_rank < 5 then raise exception 'PIM Operator or Platform Admin required' using errcode = '42501'; end if;
    if cardinality(v_pids) = 0 then raise exception 'choose universities'; end if;
    insert into pipeline.adapter_builds(provider_id, wave) select i, v_wave from unnest(v_pids) i
    on conflict (provider_id) do update set wave = excluded.wave, updated_at = now();
    return jsonb_build_object('ok', true, 'wave', v_wave, 'universities', cardinality(v_pids));

  elsif p_action = 'admit' then
    if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    if cardinality(v_pids) = 0 then raise exception 'choose universities'; end if;
    v_fields := case when p_args ? 'fields' then array(select jsonb_array_elements_text(p_args->'fields')) end;
    foreach p in array v_pids loop
      r := security.adapter_build_store_v1(p);
      -- only Ready fields are admitted, whatever was asked
      v_adapter := array(select f from jsonb_array_elements_text(r->'ready') f where f in ('intakes', 'fee', 'english', 'delivery') and (v_fields is null or f = any (v_fields)) and not (r->'fields'->f->>'admitted')::boolean);
      -- duration, campus and study level fill only what the catalogue lacks, so they run whenever a Ready field has values to add
      v_enrich := array(select f from jsonb_array_elements_text(r->'ready') f where f in ('duration', 'campus', 'study_level') and (v_fields is null or f = any (v_fields)) and (r->'fields'->f->>'new')::int > 0);
      v_m := null; v_job := null;
      if cardinality(v_adapter) > 0 then
        -- 18 Oct 2026 (first wave): the source approvals the admit jobs need are made here, once. Two admit jobs starting in the same minute
        -- each tried to create a missing one and the second failed (coverage-admit-intakes, Loyalist College, 05:40 UTC).
        insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
        select 'courses', d, security.coverage_sweep_source(p), 'approved', 'CF-CHG-20260915-247; Decision 267 (Build adapter: a Platform Admin admits Ready fields)', now(), now(), now()
          from unnest(array_remove(array['official_course_url', case when 'intakes' = any (v_adapter) then 'course_intake' end,
                                         case when 'english' = any (v_adapter) then 'course_english' end, case when 'fee' = any (v_adapter) then 'provider_current_tuition' end], null)) d
        on conflict do nothing;
        perform public.admin_uni_adapter_control('admit', jsonb_build_object('provider_id', p, 'admit', true, 'reason', 'Build adapter: ' || v_reason,
                  'fields', to_jsonb(array(select distinct f from unnest(coalesce((select u.admit_fields from pipeline.uni_adapters u where u.provider_id = p and u.admit), '{}') || v_adapter) f order by f))));
      end if;
      if cardinality(v_enrich) > 0 then
        -- 18 Oct 2026 (wave 2 check): a course tried before and held as "no value" is tried again when its page reading now gives a value
        -- for the field (new input). Only those flags are released, with the reason; the rest stay held.
        update pipeline.enrichment_flags f set state = 'released', cleared_at = now(), released_at = now(), release_kind = 'auto',
               release_reason = 'Build adapter: the course page reading now gives a value (Decision 267)', updated_at = now()
         where f.entity = 'course' and f.reason_code = 'enrich_no_value' and f.state in ('raised', 'counting')
           and f.field in (select case x when 'study_level' then 'level' else x end from unnest(v_enrich) x)
           and exists (select 1 from pipeline.coverage_course_pages g join catalogue.courses c on c.id = g.course_id and c.provider_id = p and c.lifecycle_status = 'active'
                        where g.course_id::text = f.entity_key and g.read_status = 'read' and g.identity_basis is not null
                          and case f.field when 'duration' then security.enrich_parse_duration_v1(g.candidates->'adapter_extra'->>'duration') is not null
                                           when 'level' then security.enrich_parse_level_v1(coalesce(g.candidates->'adapter_extra'->>'study_level', g.candidates->'adapter_extra'->>'aqf_level')) is not null
                                           when 'campus' then nullif(btrim(coalesce(g.candidates->'adapter_extra'->>'campus', g.candidates->'adapter_extra'->>'location')), '') is not null
                                           else false end);
        v_job := public.admin_enrich_fields('start', jsonb_build_object('provider_ids', jsonb_build_array(p), 'reason', 'Build adapter: ' || v_reason,
                  'fields', to_jsonb(array(select case f when 'study_level' then 'level' else f end from unnest(v_enrich) f))));
      end if;
      if 'majors' in (select jsonb_array_elements_text(r->'ready')) and (v_fields is null or 'majors' = any (v_fields)) and (r->'fields'->'majors'->>'new')::int > 0 then
        v_m := security.adapter_build_admit_majors_v1(p);
      end if;
      v_item := jsonb_build_object('provider_id', p, 'adapter_fields', to_jsonb(v_adapter), 'enrich_fields', to_jsonb(v_enrich), 'enrich_job', v_job->'job_id', 'majors_written', v_m,
                              'left_for_review', r->'review', 'not_ready', r->'not_ready');
      update pipeline.adapter_builds set admitted = admitted
               || coalesce((select jsonb_object_agg(f, jsonb_build_object('at', now(), 'by', auth.uid(), 'job_id', v_job->'job_id')) from unnest(v_enrich) f), '{}'::jsonb)
               || case when v_m is not null then jsonb_build_object('majors', jsonb_build_object('at', now(), 'by', auth.uid(), 'written', v_m)) else '{}'::jsonb end,
             updated_at = now()
       where provider_id = p;
      v_done := v_done || v_item;
    end loop;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('adapters', 'build_admit', cardinality(v_pids) || ' universities', jsonb_build_object('decision', 267, 'reason', v_reason, 'fields_asked', to_jsonb(v_fields), 'done', v_done), auth.uid());
    return jsonb_build_object('admitted', v_done);
  end if;
  raise exception 'unknown action %', p_action using errcode = '22023';
end $function$;



do $post$ declare v jsonb; begin
  if not exists (select 1 from pg_proc where oid = 'public.admin_adapter_build(text,jsonb)'::regprocedure and prosrc ~ 'the course page reading now gives a value') then raise exception 'post-check: build'; end if;
  if length(pg_get_functiondef('security.enrich_fields_slice_v1(uuid,integer)'::regprocedure)) < 5000 then raise exception 'post-check: slice length'; end if;
  v := security.consumer_api_check_v1()->'drift';
  if jsonb_array_length(v) > 0 then raise exception 'post-check: consumer API drift %', v; end if;
end $post$;
