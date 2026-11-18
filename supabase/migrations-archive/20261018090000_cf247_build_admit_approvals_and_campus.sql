-- CF-247 Decision 267 follow-up 2 (18 Oct 2026, first Build adapter wave). Platform Admin 16:34 "Suggest and proceed with next step".
-- Two findings from the first wave of 12 universities:
-- 1 coverage-admit-intakes failed once (05:40 UTC): coverage-admit and coverage-admit-intakes start in the same minute, and both tried to
--   create Loyalist College's missing intake approval (search.enrichment_source_gates); the second hit the key. The next run succeeds.
--   One click now creates the approvals its admitted fields need, with on conflict do nothing, before the adapter admits them. The admit
--   jobs themselves are unchanged.
-- 2 College of the North Atlantic was Ready for campus although its adapter reads page navigation as the campus: the catalogue held no
--   campus to compare with, so nothing disagreed. Enrichment refused all 115 (no campus list), so nothing wrong was written. A campus
--   reading now agrees only when it names one of the university's own campuses; a university with no campus list is Review, never Ready.
-- Replaces: public.admin_adapter_build (approvals made at admit); security.adapter_build_fields_v1 (campus agreement)
-- Retires: nothing
-- Nothing dropped or deleted. The consumer API is not touched (checked at the end).

do $guard$ begin
  if md5(pg_get_functiondef('public.admin_adapter_build(text,jsonb)'::regprocedure)) <> '3d301d9c786776704868a183f8c478bb' then
    raise exception 'public.admin_adapter_build is not the definition this change replaces';
  end if;
  if md5(pg_get_functiondef('security.adapter_build_fields_v1(uuid)'::regprocedure)) <> '96fda6f52cbd77022ec0b1346c015ea9' then
    raise exception 'security.adapter_build_fields_v1 is not the definition this change replaces';
  end if;
end $guard$;

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


create or replace function security.adapter_build_fields_v1(p_provider_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  v_min_read numeric := coalesce((security.firecrawl_setting('eval_field_share') #>> '{}')::numeric, 0.5);
  v_min_agree numeric := coalesce((security.firecrawl_setting('qualify_agree_share') #>> '{}')::numeric, 0.9);
  v_tol numeric := security.pipeline_num_v1('build.duration_tolerance_years', 0.25);
  v_pages int; v_out jsonb := '{}'::jsonb; r record; v_share numeric; v_agree numeric; v_state text; v_why text;
  u pipeline.uni_adapters%rowtype; b pipeline.adapter_builds%rowtype; v_adds int := 0;
begin
  select * into u from pipeline.uni_adapters where provider_id = p_provider_id;
  select * into b from pipeline.adapter_builds where provider_id = p_provider_id;
  -- 18 Oct 2026 (first wave): measured on the pages of active courses only (archived courses are not admitted)
  v_pages := (select count(*) from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id and c.lifecycle_status = 'active'
               where pg.provider_id = p_provider_id and pg.read_status = 'read' and pg.identity_basis is not null);
  for r in
    with pg as (
      select pg.course_id, pg.candidates c, pg.candidates->'adapter_extra' x, true act from pipeline.coverage_course_pages pg
        join catalogue.courses c0 on c0.id = pg.course_id and c0.lifecycle_status = 'active'
       where pg.provider_id = p_provider_id and pg.read_status = 'read' and pg.identity_basis is not null),
    d as (
      select 'duration' field, count(*) filter (where y.rd) rd, count(*) filter (where y.rd and y.held and y.eq) ag, count(*) filter (where y.rd and y.held and not y.eq) df, count(*) filter (where y.rd and not y.held and y.act) nw
        from (select pg.act, pv is not null rd, c.duration_value is not null held,
                     abs(coalesce(security.adapter_build_years_v1((pv->>'value')::numeric, pv->>'unit'), -99) - coalesce(security.adapter_build_years_v1(c.duration_value, c.duration_unit), 99)) <= v_tol eq
                from pg join catalogue.courses c on c.id = pg.course_id
                cross join lateral (select security.enrich_parse_duration_v1(pg.x->>'duration') pv) z) y
      union all
      select 'study_level', count(*) filter (where y.rd), count(*) filter (where y.rd and y.held and y.eq), count(*) filter (where y.rd and y.held and not y.eq), count(*) filter (where y.rd and not y.held and y.act)
        from (select pg.act, lv.id is not null rd, c.study_level_id is not null held,
                     security.adapter_build_level_family_v1(lv.short_code) = security.adapter_build_level_family_v1(hl.short_code) eq
                from pg join catalogue.courses c on c.id = pg.course_id
                left join ref.study_levels lv on lv.id = security.enrich_parse_level_v1(coalesce(pg.x->>'study_level', pg.x->>'aqf_level'))
                left join ref.study_levels hl on hl.id = c.study_level_id) y
      union all
      select 'campus', count(*) filter (where y.rd), count(*) filter (where y.rd and y.known), count(*) filter (where y.rd and not y.known), count(*) filter (where y.rd and y.known and not y.held and y.act)
        -- 18 Oct 2026 (first wave): a campus reading agrees when it names one of the university's own campuses; a reading that names none
        -- (page navigation, "Distance and online") differs, so a university with no campus list is never Ready for campus
        from (select pg.act, v is not null rd,
                     exists (select 1 from catalogue.course_campuses cc where cc.course_id = pg.course_id) held,
                     exists (select 1 from catalogue.campuses k where k.provider_id = p_provider_id
                                and length(btrim(regexp_replace(k.name, '\s*campus\s*', ' ', 'gi'))) >= 3  -- fixed: a name shorter than this matches anything
                                and strpos(lower(v), lower(btrim(regexp_replace(k.name, '\s*campus\s*', ' ', 'gi')))) > 0) known
                from pg cross join lateral (select nullif(btrim(coalesce(pg.x->>'campus', pg.x->>'location')), '') v) z) y
      union all
      select 'majors', count(*) filter (where y.rd), count(*) filter (where y.rd and y.held and y.eq), count(*) filter (where y.rd and y.held and not y.eq), count(*) filter (where y.rd and not y.held and y.act)
        from (select pg.act, v is not null rd,
                     exists (select 1 from catalogue.course_specialisations s where s.course_id = pg.course_id and s.status = 'active') held,
                     (select coalesce(array_agg(lower(s.name) order by lower(s.name)), '{}') from catalogue.course_specialisations s where s.course_id = pg.course_id and s.status = 'active')
                       = security.adapter_build_majors_v1(v) eq
                from pg cross join lateral (select nullif(btrim(pg.x->>'majors'), '') v) z) y
      union all
      select 'intakes', count(*) filter (where y.rd and not y.ex), count(*) filter (where y.rd and not y.ex and y.held and y.eq), count(*) filter (where y.rd and not y.ex and y.held and not y.eq), count(*) filter (where y.rd and not y.ex and not y.held)
        from (select (pg.c->>'intakes_by' = 'adapter') rd, security.uni_adapter_excluded(pg.course_id, 'intakes') ex, h.itk is not null held, (h.itk = a.itk) eq
                from pg
                cross join lateral (select array_agg(distinct m order by m) itk from jsonb_array_elements_text(coalesce(pg.c->'intakes', '[]'::jsonb)) m) a
                cross join lateral (select array_agg(distinct i.intake_label order by i.intake_label) itk from catalogue.course_intakes i where i.course_id = pg.course_id and i.status = 'active') h) y
      union all
      select 'fee', count(*) filter (where y.rd and not y.ex), count(*) filter (where y.rd and not y.ex and y.held and y.eq), count(*) filter (where y.rd and not y.ex and y.held and not y.eq), count(*) filter (where y.rd and not y.ex and not y.held)
        from (select (pg.c->>'fee_by' = 'adapter' and nullif(pg.c->'fee'->>'value', '') is not null) rd, security.uni_adapter_excluded(pg.course_id, 'fee') ex,
                     exists (select 1 from catalogue.course_fees f where f.course_id = pg.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international') held,
                     exists (select 1 from catalogue.course_fees f where f.course_id = pg.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and f.amount = nullif(pg.c->'fee'->>'value', '')::numeric) eq
                from pg) y
      union all
      select 'english', count(*) filter (where y.rd and not y.ex), count(*) filter (where y.rd and not y.ex and y.held and y.eq), count(*) filter (where y.rd and not y.ex and y.held and not y.eq), count(*) filter (where y.rd and not y.ex and not y.held)
        from (select (pg.c->>'english_by' = 'adapter' and nullif(pg.c->'english'->>'ielts_overall', '') is not null) rd, security.uni_adapter_excluded(pg.course_id, 'english') ex,
                     h.score is not null held, (h.score = nullif(pg.c->'english'->>'ielts_overall', '')::numeric) eq
                from pg
                cross join lateral (select max(e.overall_score) score from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id and t.code = 'IELTS' where e.course_id = pg.course_id and e.status = 'active') h) y
      union all
      select 'delivery', count(*) filter (where y.rd and not y.ex), count(*) filter (where y.rd and not y.ex and y.held and y.eq), count(*) filter (where y.rd and not y.ex and y.held and not y.eq), count(*) filter (where y.rd and not y.ex and not y.held)
        from (select (x0.mode is not null and x0.mode <> 'on_campus_and_online') rd, security.uni_adapter_excluded(pg.course_id, 'delivery') ex,
                     co.delivery_mode is not null held, (co.delivery_mode = x0.mode) eq
                from pg join catalogue.courses co on co.id = pg.course_id
                cross join lateral (select security.delivery_mode_from_text(pg.x->>'mode') mode) x0) y)
    select * from d
  loop
    v_share := case when v_pages > 0 then round(r.rd::numeric / v_pages, 3) else 0 end;
    v_agree := case when (r.ag + r.df) > 0 then round(r.ag::numeric / (r.ag + r.df), 3) end;
    v_out := v_out || jsonb_build_object(r.field, jsonb_build_object('read', r.rd, 'agree', r.ag, 'differ', r.df, 'new', r.nw, 'read_share', v_share, 'agree_share', v_agree));
  end loop;
  for r in select f, ord from unnest(array['intakes', 'fee', 'english', 'delivery', 'duration', 'campus', 'study_level', 'majors']) with ordinality t(f, ord) loop
    if not v_out ? r.f then v_out := v_out || jsonb_build_object(r.f, jsonb_build_object('read', 0, 'agree', 0, 'differ', 0, 'new', 0, 'read_share', 0, 'agree_share', null)); end if;
    v_share := (v_out->r.f->>'read_share')::numeric; v_agree := (v_out->r.f->>'agree_share')::numeric;
    if (v_out->r.f->>'read')::int = 0 then v_state := 'not_ready';
      v_why := case when u.provider_id is null then 'no adapter yet' when r.f = 'majors' and not (coalesce(u.patterns, '{}'::jsonb) ? 'majors') then 'the adapter does not read majors yet' else 'not read by the adapter' end;
    elsif v_share < v_min_read then v_state := 'review'; v_why := format('read on %s of %s pages, under the %s%% needed', v_out->r.f->>'read', v_pages, round(v_min_read * 100));
    elsif v_agree is not null and v_agree < v_min_agree then v_state := 'review';
      v_why := case when r.f = 'campus' then format('%s of %s readings name no campus the university has%s', v_out->r.f->>'differ', (v_out->r.f->>'agree')::int + (v_out->r.f->>'differ')::int,
                                                    case when not exists (select 1 from catalogue.campuses k where k.provider_id = p_provider_id) then ' (it has no campus list yet: Enrich fields can build one)' else '' end)
                    else format('%s of %s readings differ from the catalogue', v_out->r.f->>'differ', (v_out->r.f->>'agree')::int + (v_out->r.f->>'differ')::int) end;
    else v_state := 'ready'; v_why := case when (v_out->r.f->>'new')::int > 0 then format('adds %s values the catalogue does not hold', v_out->r.f->>'new') else 'agrees with the catalogue' end; end if;
    v_out := jsonb_set(v_out, array[r.f], (v_out->r.f) || jsonb_build_object('state', v_state, 'why', v_why, 'order', r.ord,
              'admitted', case when r.f in ('intakes', 'fee', 'english', 'delivery') then coalesce(u.admit, false) and r.f = any (coalesce(u.admit_fields, '{}'))
                               else coalesce(b.admitted, '{}'::jsonb) ? r.f end));
    if v_state = 'ready' then v_adds := v_adds + (v_out->r.f->>'new')::int; end if;
  end loop;
  return jsonb_build_object('provider_id', p_provider_id, 'pages_read', v_pages, 'has_adapter', u.provider_id is not null, 'fields', v_out,
    'ready', (select coalesce(jsonb_agg(k order by (v->>'order')::int), '[]'::jsonb) from jsonb_each(v_out) x(k, v) where v->>'state' = 'ready'),
    'review', (select coalesce(jsonb_agg(k order by (v->>'order')::int), '[]'::jsonb) from jsonb_each(v_out) x(k, v) where v->>'state' = 'review'),
    'not_ready', (select coalesce(jsonb_agg(k order by (v->>'order')::int), '[]'::jsonb) from jsonb_each(v_out) x(k, v) where v->>'state' = 'not_ready'),
    'adds', v_adds, 'min_read', v_min_read, 'min_agree', v_min_agree, 'measured_at', now());
end $function$;


do $again$ declare p uuid; begin
  for p in select provider_id from pipeline.uni_adapters where enabled loop perform security.adapter_build_store_v1(p); end loop;
end $again$;

do $post$ declare v jsonb; begin
  if (select readiness->'fields'->'campus'->>'state' from pipeline.adapter_builds where provider_id = '4812a855-4fbc-43ce-9029-137c80327361') = 'ready' then
    raise exception 'post-check: College of the North Atlantic still Ready for campus';
  end if;
  if exists (select 1 from pipeline.adapter_builds where jsonb_array_length(readiness->'ready') + jsonb_array_length(readiness->'review') + jsonb_array_length(readiness->'not_ready') <> 8) then raise exception 'post-check: eight fields'; end if;
  if not exists (select 1 from pg_proc where oid = 'public.admin_adapter_build(text,jsonb)'::regprocedure and prosrc ~ 'on conflict do nothing') then raise exception 'post-check: approvals'; end if;
  v := security.consumer_api_check_v1()->'drift';
  if jsonb_array_length(v) > 0 then raise exception 'post-check: consumer API drift %', v; end if;
end $post$;
