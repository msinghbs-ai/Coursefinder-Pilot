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
  -- 22 Oct 2026 (Platform Admin 11:42): items of unpublished providers in automatic tasks (standing gap queue, automatic plans) are settled
  -- without the AI; the gap queue asks for them again once the provider is published (reason 'provider unpublished'). A task a person started runs.
  update pipeline.field_enrich_items e set state = 'skipped', reason = 'provider unpublished', leased_until = null, updated_at = now()
    from pipeline.admin_jobs j
   where j.id = e.job_id and e.state = 'ai' and (coalesce((j.args->>'standing')::boolean, false) or j.args->>'plan_mode' = 'auto')
     and exists (select 1 from security.provider_hidden_v1 h where h.provider_id = e.provider_id);
  with pick as (select e.id from pipeline.field_enrich_items e
                 where (e.state = 'ai' or (e.state = 'leased' and e.leased_until < now())) and e.attempts < 3
                 order by e.job_id, (e.course_id is null), e.course_id, e.id limit v_lim for update skip locked),  -- a course's fields together
  upd as (update pipeline.field_enrich_items e set state = 'leased', leased_until = now() + make_interval(mins => 4), attempts = e.attempts + 1, updated_at = now()
            from pick where e.id = pick.id returning e.*)
  select jsonb_build_object('model', s.model_identifier, 'model_code', s.model_code,
    'pages', coalesce((select jsonb_agg(g.x) from (
                         select jsonb_build_object('course_id', u.course_id, 'storage_path', min(u.storage_path), 'title', min(c.canonical_title), 'provider', min(coalesce(p.display_name, p.canonical_name)),
                                  'items', jsonb_agg(jsonb_build_object('item_id', u.id, 'field', u.field,
                                    'hint', case when u.reason = 'the quote is not on the page' then 'last time the quote given for this field was not found on the page' end))) x
                           from upd u join catalogue.courses c on c.id = u.course_id join catalogue.providers p on p.id = u.provider_id
                          where u.source = 'ai_stored' and u.course_id is not null group by u.course_id) g), '[]'::jsonb),
    'titles', coalesce((select jsonb_agg(jsonb_build_object('item_id', u.id, 'field', u.field, 'title', c.canonical_title, 'level', sl.name, 'provider', coalesce(p.display_name, p.canonical_name)))
                        from upd u join catalogue.courses c on c.id = u.course_id join catalogue.providers p on p.id = u.provider_id left join ref.study_levels sl on sl.id = c.study_level_id
                       where u.source = 'ai_title'), '[]'::jsonb),
    'campus_lists', coalesce((select jsonb_agg(jsonb_build_object('item_id', u.id, 'provider', coalesce(p.display_name, p.canonical_name), 'storage_path', u.storage_path,
                         'names', (select coalesce(jsonb_agg(jsonb_build_object('text', q, 'pages', n) order by n desc), '[]'::jsonb)
                                     from (select c.quote q, count(*) n from pipeline.field_enrich_items c where c.job_id = u.job_id and c.provider_id = u.provider_id and c.field = 'campus' and c.quote is not null group by c.quote order by 2 desc limit 80) z)))
                        from upd u join catalogue.providers p on p.id = u.provider_id where u.field = 'campus_list'), '[]'::jsonb),
    'regions', coalesce((select jsonb_agg(jsonb_build_object('item_id', u.id, 'provider', coalesce(p.display_name, p.canonical_name), 'country', k.name,
                         'cities', (select coalesce(jsonb_agg(distinct btrim(c2.city)), '[]'::jsonb) from catalogue.campuses c2
                                     where c2.provider_id = u.provider_id and c2.status = 'active' and c2.subdivision_id is null and nullif(btrim(c2.city), '') is not null),
                         'regions', (select coalesce(jsonb_agg(s2.name order by s2.name), '[]'::jsonb) from ref.subdivisions s2 where s2.country_id = p.country_id)))
                        from upd u join catalogue.providers p on p.id = u.provider_id join ref.countries k on k.id = p.country_id where u.field = 'campus_region'), '[]'::jsonb),
    'addresses', coalesce((select jsonb_agg(jsonb_build_object('item_id', u.id, 'provider_id', u.provider_id, 'provider', coalesce(p.display_name, p.canonical_name), 'storage_path', u.storage_path,
                         'website', case when u.source = 'scraper' then p.website end, 'country', (select k.iso_alpha2 from ref.countries k where k.id = p.country_id)))
                        from upd u join catalogue.providers p on p.id = u.provider_id where u.field = 'provider_address'), '[]'::jsonb),
    'entry', jsonb_build_object('model', coalesce(security.toolset_setting('pipeline', 'entry.matrix_model') #>> '{}', 'openai/gpt-4.1-mini'),
                                'page_chars', security.pipeline_num_v1('entry.course_page_chars', 100000)::int),  -- CF-247 Track C Step B: the pinned entry model
    'fields', (select jsonb_agg(jsonb_build_object('code', f.code, 'name', f.name) order by f.code) from ref.fields_of_study f where f.code ~ '^asced-\d{4}$' and f.code !~ '00$'),
    'levels', (select jsonb_agg(jsonb_build_object('code', l.short_code, 'name', l.name) order by l.sort_order) from ref.study_levels l where l.short_code is not null))
    into v;
  return v;
end $function$
;
