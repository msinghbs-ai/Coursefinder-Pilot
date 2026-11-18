-- CF-247 Decision 267 follow-up 4 (18 Oct 2026, second Build adapter wave). Platform Admin 17:20 "Proceed and always consolidate next steps".
-- Wave 2 (30 universities) wrote 223 fees, 43 durations and 10 intakes, and showed two places where readiness promised more than admission
-- delivers:
-- 1 Fee: 122 fees were held back by the admit cross-check (more than admit.fee_crosscheck_pct from the CRICOS registered course total; for
--   example 8,000 a year for 24 months against 24,600 registered). Readiness now counts such a reading as differing, not as a value to add,
--   with the same rule and the same setting.
-- 2 English: readiness compared only IELTS overall scores, so a course holding English through its approved policy (a level, skill
--   minimums or another test) looked empty. A course holding any active English requirement is now held; an IELTS score is compared only
--   where the course holds one.
-- Admission itself is unchanged (security.fee_crosscheck_guard_v1, coverage admission). Readiness is measured again.
-- Replaces: security.adapter_build_fields_v1 (fee cross-check and English held)
-- Retires: nothing
-- Nothing dropped or deleted. search.course_documents is only read. The consumer API is not touched (checked at the end).

do $guard$ begin
  if md5(pg_get_functiondef('security.adapter_build_fields_v1(uuid)'::regprocedure)) <> '178b0fdbbb3ed2b359d612de7a2f5a47' then
    raise exception 'security.adapter_build_fields_v1 is not the definition this change replaces';
  end if;
end $guard$;

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
      -- 18 Oct 2026 (wave 2): a fee the admit cross-check would hold back (more than admit.fee_crosscheck_pct from the CRICOS registered
      -- course total) differs; it is not a value the click would add
      select 'fee', count(*) filter (where y.rd and not y.ex), count(*) filter (where y.rd and not y.ex and ((y.held and y.eq) or (not y.held and not y.far))),
             count(*) filter (where y.rd and not y.ex and ((y.held and not y.eq) or (not y.held and y.far))), count(*) filter (where y.rd and not y.ex and not y.held and not y.far)
        from (select (pg.c->>'fee_by' = 'adapter' and nullif(pg.c->'fee'->>'value', '') is not null) rd, security.uni_adapter_excluded(pg.course_id, 'fee') ex,
                     exists (select 1 from catalogue.course_fees f where f.course_id = pg.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international') held,
                     exists (select 1 from catalogue.course_fees f where f.course_id = pg.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and f.amount = nullif(pg.c->'fee'->>'value', '')::numeric) eq,
                     coalesce((select ck.months >= 12 and abs(ck.fee * ck.months / 12.0 - ck.reg) > security.pipeline_num_v1('admit.fee_crosscheck_pct', 25) / 100.0 * ck.reg
                                 from (select case when (pg.c->'fee'->>'value') ~ '^[0-9]+(\.[0-9]+)?$' then (pg.c->'fee'->>'value')::numeric end fee, d.regulatory_tuition_amount reg,
                                              case co.duration_unit when 'months' then co.duration_value when 'weeks' then co.duration_value * 12 / 52.0 when 'years' then co.duration_value * 12 end months  -- fixed: calendar units
                                         from search.course_documents d join catalogue.courses co on co.id = d.course_id
                                        where d.course_id = pg.course_id and d.regulatory_tuition_basis = 'registered_total_course' and d.regulatory_tuition_amount > 0) ck
                                where ck.fee is not null), false) far
                from pg) y
      union all
      select 'english', count(*) filter (where y.rd and not y.ex), count(*) filter (where y.rd and not y.ex and y.held and y.eq), count(*) filter (where y.rd and not y.ex and y.held and not y.eq), count(*) filter (where y.rd and not y.ex and not y.held)
        from (select (pg.c->>'english_by' = 'adapter' and nullif(pg.c->'english'->>'ielts_overall', '') is not null) rd, security.uni_adapter_excluded(pg.course_id, 'english') ex,
                     -- 18 Oct 2026 (wave 2): a course holding any English requirement (a policy level, another test) is held; only an IELTS score is compared
                     exists (select 1 from catalogue.course_english_requirements e2 where e2.course_id = pg.course_id and e2.status = 'active') held,
                     (h.score is null or h.score = nullif(pg.c->'english'->>'ielts_overall', '')::numeric) eq
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
  if (select (readiness->'fields'->'english'->>'new')::int from pipeline.adapter_builds where provider_id = 'd02a8a1b-f4be-4d98-a857-242e66a0f354') > 0 then
    raise exception 'post-check: Canberra Institute of Technology English still shows values to add';
  end if;
  if exists (select 1 from pipeline.adapter_builds where jsonb_array_length(readiness->'ready') + jsonb_array_length(readiness->'review') + jsonb_array_length(readiness->'not_ready') <> 8) then raise exception 'post-check: eight fields'; end if;
  v := security.consumer_api_check_v1()->'drift';
  if jsonb_array_length(v) > 0 then raise exception 'post-check: consumer API drift %', v; end if;
end $post$;
