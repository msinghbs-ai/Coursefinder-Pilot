CREATE OR REPLACE FUNCTION public.admin_adapter_builder_basics(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_pid uuid; v_q text; v jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'PIM Operator or Platform Admin required' using errcode = '42501'; end if;
  if p_action = 'search' then
    v_q := btrim(coalesce(p_args->>'q', ''));
    if length(v_q) < 2 then return jsonb_build_object('providers', '[]'::jsonb); end if;
    select coalesce(jsonb_agg(x order by x->>'name'), '[]'::jsonb) into v from (
      select jsonb_build_object('provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'website', p.website,
               'country', (select k.iso_alpha2 from ref.countries k where k.id = p.country_id),
               'courses', (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active'),
               'adapter', (select case when not u.enabled then 'off' when u.admit then 'admitting' else 'testing' end from pipeline.uni_adapters u where u.provider_id = p.id)) x
        from catalogue.providers p
       where p.lifecycle_status = 'active' and (coalesce(p.display_name, p.canonical_name) ilike '%' || v_q || '%' or p.website ilike '%' || v_q || '%')
       order by (exists (select 1 from pipeline.uni_adapters u where u.provider_id = p.id)) desc, coalesce(p.display_name, p.canonical_name) limit 20) s;
    return jsonb_build_object('providers', v);
  end if;
  if p_action <> 'basics' then raise exception 'unknown action'; end if;
  v_pid := nullif(p_args->>'provider_id', '')::uuid;
  if not exists (select 1 from catalogue.providers where id = v_pid) then raise exception 'unknown provider'; end if;
  select jsonb_build_object(
    'provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'website', p.website,
    'country', (select k.iso_alpha2 from ref.countries k where k.id = p.country_id),
    'courses', (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active'),
    'pages', (select jsonb_build_object('stored', count(*), 'read', count(*) filter (where pg.read_status = 'read'),
                                        'needs_render', count(*) filter (where pg.read_status in ('needs_render', 'blocked')))
                from pipeline.coverage_course_pages pg where pg.provider_id = p.id),
    'adapter', (select jsonb_build_object('enabled', u.enabled, 'admit', u.admit, 'admit_fields', u.admit_fields, 'notes', left(coalesce(u.notes, ''), 600),
                                          'updated_at', u.updated_at, 'patterns', (select count(*) from jsonb_object_keys(coalesce(u.patterns, '{}'::jsonb))),
                                          'json_paths', (select count(*) from jsonb_object_keys(coalesce(u.json_paths, '{}'::jsonb))))
                  from pipeline.uni_adapters u where u.provider_id = p.id),
    'qualify', case when exists (select 1 from pipeline.uni_adapters u where u.provider_id = p.id) then security.adapter_qualify_one_v1(p.id, 0.5, 0.9) end,
    'central', (select coalesce(jsonb_agg(jsonb_build_object('kind', f.kind, 'url', f.url, 'status', f.status, 'found_via', f.found_via,
                         'decision', f.decision) order by f.kind, f.rank, f.updated_at desc), '[]'::jsonb)
                  from pipeline.provider_fact_sources f where f.provider_id = p.id and f.status not in ('failed', 'no_values')),
    'suggested', (select coalesce(jsonb_agg(jsonb_build_object('kind', s.kind, 'url', s.url, 'title', s.title)), '[]'::jsonb) from (
                    select k.kind, u.url, u.title, row_number() over (partition by k.kind order by length(u.url)) rn
                      from pipeline.coverage_provider_urls u
                      cross join lateral (select case
                               when u.url ~* '(key-?dates|academic-?calendar|semester-?dates|term-?dates|important-?dates|principal-?dates)' then 'intake_calendar'
                               when u.url ~* '(international.*(fee|tuition)|(fee|tuition).*international|fee-?schedule|tuition-?fees)' then 'fee_schedule'
                               when u.url ~* '(english-?language-?requirement|english-?requirement|english-?proficiency)' then 'english_policy' end kind) k
                     where u.provider_id = p.id and k.kind is not null
                       and not exists (select 1 from pipeline.provider_fact_sources f where f.provider_id = p.id and f.kind = k.kind and f.url = u.url)) s where s.rn <= 3),
    'can_manage', v_rank >= 6)
    into v from catalogue.providers p where p.id = v_pid;
  return v;
end $function$
