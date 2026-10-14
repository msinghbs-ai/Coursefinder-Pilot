-- CF-247 v2.15.273 (live trial on one university): the AI step took the next items in creation order, so one call carried one field of
-- twelve courses. It now takes a course's fields together (one page read answers them all) and sizes each call from the setting
-- enrich.ai_items_per_call. Nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"public.svc_enrich_ai_next(integer)": "904dc8e2e19f169f23be93262919e05e", "security.enrich_ai_fire_v1()": "6d8552c568dec604aace8813b033ae79"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values ('pipeline', 'enrich.ai_items_per_call', 'Enrich fields: items in one AI call', 'Fields read in one worker call (a course page answers all of its fields at once).', 'number', to_jsonb(30), 5, 40, 'items', 104, 'CF-247 v2.15.273: batching after the live trial', 'Job sizes', 'Enrich fields tasks')
on conflict do nothing;

CREATE OR REPLACE FUNCTION public.svc_enrich_ai_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; s record; v_lim int := greatest(1, least(coalesce(p_limit, 10), 40));
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select model_identifier, model_code into s from pipeline.central_ai_settings where id = 1;
  with pick as (select e.id from pipeline.field_enrich_items e
                 where (e.state = 'ai' or (e.state = 'leased' and e.leased_until < now())) and e.attempts < 3
                 order by e.job_id, (e.course_id is null), e.course_id, e.id limit v_lim for update skip locked),  -- a course's fields together
  upd as (update pipeline.field_enrich_items e set state = 'leased', leased_until = now() + make_interval(mins => 4), attempts = e.attempts + 1, updated_at = now()
            from pick where e.id = pick.id returning e.*)
  select jsonb_build_object('model', s.model_identifier, 'model_code', s.model_code,
    'pages', coalesce((select jsonb_agg(g.x) from (
                         select jsonb_build_object('course_id', u.course_id, 'storage_path', min(u.storage_path), 'title', min(c.canonical_title), 'provider', min(coalesce(p.display_name, p.canonical_name)),
                                  'items', jsonb_agg(jsonb_build_object('item_id', u.id, 'field', u.field))) x
                           from upd u join catalogue.courses c on c.id = u.course_id join catalogue.providers p on p.id = u.provider_id
                          where u.source = 'ai_stored' and u.course_id is not null group by u.course_id) g), '[]'::jsonb),
    'titles', coalesce((select jsonb_agg(jsonb_build_object('item_id', u.id, 'field', u.field, 'title', c.canonical_title, 'level', sl.name, 'provider', coalesce(p.display_name, p.canonical_name)))
                        from upd u join catalogue.courses c on c.id = u.course_id join catalogue.providers p on p.id = u.provider_id left join ref.study_levels sl on sl.id = c.study_level_id
                       where u.source = 'ai_title'), '[]'::jsonb),
    'campus_lists', coalesce((select jsonb_agg(jsonb_build_object('item_id', u.id, 'provider', coalesce(p.display_name, p.canonical_name), 'storage_path', u.storage_path,
                         'names', (select coalesce(jsonb_agg(jsonb_build_object('text', q, 'pages', n) order by n desc), '[]'::jsonb)
                                     from (select c.quote q, count(*) n from pipeline.field_enrich_items c where c.job_id = u.job_id and c.provider_id = u.provider_id and c.field = 'campus' and c.quote is not null group by c.quote order by 2 desc limit 80) z)))
                        from upd u join catalogue.providers p on p.id = u.provider_id where u.field = 'campus_list'), '[]'::jsonb),
    'addresses', coalesce((select jsonb_agg(jsonb_build_object('item_id', u.id, 'provider_id', u.provider_id, 'provider', coalesce(p.display_name, p.canonical_name), 'storage_path', u.storage_path,
                         'website', case when u.source = 'scraper' then p.website end, 'country', (select k.iso_alpha2 from ref.countries k where k.id = p.country_id)))
                        from upd u join catalogue.providers p on p.id = u.provider_id where u.field = 'provider_address'), '[]'::jsonb),
    'fields', (select jsonb_agg(jsonb_build_object('code', f.code, 'name', f.name) order by f.code) from ref.fields_of_study f where f.code ~ '^asced-\d{4}$' and f.code !~ '00$'),
    'levels', (select jsonb_agg(jsonb_build_object('code', l.short_code, 'name', l.name) order by l.sort_order) from ref.study_levels l where l.short_code is not null))
    into v;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION security.enrich_ai_fire_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_open int; v_max int := security.pipeline_num_v1('enrich.ai_calls_at_once', 2)::int; v_due int; v_sent int := 0;
begin
  if not security.ai_use_allowed_v1('enrich_fields') then return 0; end if;
  select count(*) into v_due from pipeline.field_enrich_items where state = 'ai' or (state = 'leased' and leased_until < now());
  if v_due = 0 then return 0; end if;
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'enrich_ai' and l.created_at > now() - make_interval(mins => 3)
     and not exists (select 1 from net._http_response r where r.id = l.request_id);
  while v_open + v_sent < v_max and v_sent * 10 < v_due loop
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'enrich_ai', 'limit', security.pipeline_num_v1('enrich.ai_items_per_call', 30)::int));
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end $function$;

do $post$
declare v_expected jsonb := '{"public.svc_enrich_ai_next(integer)": "63240ffa03d7b5719b138a4088c5c7c4", "security.enrich_ai_fire_v1()": "bea52a45b124e3e9d9b3fd17cb92620a"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.273 batching post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
