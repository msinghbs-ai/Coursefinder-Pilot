-- CF-247 Decision 267 follow-up (18 Oct 2026, first Build adapter wave): readiness is measured on the pages of active courses only.
-- Platform Admin 16:34 "Suggest and proceed with next step". The first wave showed three Canadian colleges whose readiness came mostly
-- from pages of inactive courses (Okanagan College: 111 of 114 pages), which the adapter does not admit into, so "would add" was overstated.
-- security.adapter_build_fields_v1 now measures all eight fields itself, on active courses, the four adapter fields with the same rules as
-- qualification (security.adapter_qualify_one_v1, unchanged; the Admit route and the automatic qualification are not affected).
-- Readiness is measured again for every university with an adapter.
-- Replaces: security.adapter_build_fields_v1 (counted pages of inactive courses)
-- Retires: nothing
-- Nothing dropped or deleted. The consumer API is not touched (checked at the end).

do $guard$ begin
  if md5(pg_get_functiondef('security.adapter_build_fields_v1(uuid)'::regprocedure)) <> '602d5ab6df40864d987cec1d8dd8b701' then
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
      select 'campus', count(*) filter (where y.rd), count(*) filter (where y.rd and y.held and y.eq), count(*) filter (where y.rd and y.held and not y.eq), count(*) filter (where y.rd and not y.held and y.act)
        from (select pg.act, v is not null rd,
                     exists (select 1 from catalogue.course_campuses cc where cc.course_id = pg.course_id) held,
                     exists (select 1 from catalogue.course_campuses cc join catalogue.campuses k on k.id = cc.campus_id
                              where cc.course_id = pg.course_id
                                and strpos(lower(v), lower(btrim(regexp_replace(k.name, '\s*campus\s*', ' ', 'gi')))) > 0) eq
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
    elsif v_agree is not null and v_agree < v_min_agree then v_state := 'review'; v_why := format('%s of %s readings differ from the catalogue', v_out->r.f->>'differ', (v_out->r.f->>'agree')::int + (v_out->r.f->>'differ')::int);
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
  if exists (select 1 from pg_proc where oid = 'security.adapter_build_fields_v1(uuid)'::regprocedure and prosrc ~ 'adapter_qualify_one_v1') then raise exception 'post-check: still copies qualification'; end if;
  if exists (select 1 from pipeline.adapter_builds where jsonb_array_length(readiness->'ready') + jsonb_array_length(readiness->'review') + jsonb_array_length(readiness->'not_ready') <> 8) then raise exception 'post-check: eight fields'; end if;
  if (select pages_read from pipeline.adapter_builds where provider_id = '5b6ad653-99f7-4347-a56e-f0d2928bd34d') > 10 then raise exception 'post-check: Okanagan still counts inactive pages'; end if;
  v := security.consumer_api_check_v1()->'drift';
  if jsonb_array_length(v) > 0 then raise exception 'post-check: consumer API drift %', v; end if;
end $post$;
