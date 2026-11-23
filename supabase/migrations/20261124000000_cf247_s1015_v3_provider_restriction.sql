-- CF-247 s1015 (S1-RM-Design; Platform Admin 23 Nov 2026 23:47 AEDT, overnight brief item 2: REQ-118 "restriction_mode & restriction_markets
-- (additive v3 read)"). Website API v3 provider items gain two keys read from pipeline.provider_representation (s1012):
--   restriction_mode     include | exclude | none, null when no row is held or the recorded agreement ended before today (Melbourne)
--   restriction_markets  ISO 3166-1 alpha-2 codes, [] when the mode is none, null when nothing is held
-- representation_status itself is not served (the brief names only the restriction fields). v3 is not yet live and open to additions
-- (Decision 277); the frozen v2 surface is not touched (75/48 checked before and after). The provider item is replaced only from the
-- definition it was written against (md5 checked) and keeps every existing key.
-- G1: no job. G2: no operational value. Manual locks and active cron jobs checked unchanged.
-- Replaces: nothing
-- Retires: nothing
set local lock_timeout = '5s';  -- fixed: lock wait for the function replace

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('public.website_v3_provider_item(jsonb)'::regprocedure)) <> 'c3262f054919709d935989793b8297a9' then
    raise exception 'guard: website_v3_provider_item is not the definition this change was written against';
  end if;
end $g$;
create temp table s1015_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1015_cron on commit drop as select count(*) n from cron.job where active;

create or replace function security.provider_restriction_v3_v1(p_provider uuid)
returns jsonb language sql stable security definer set search_path = '' as $function$
  select coalesce((select jsonb_build_object('restriction_mode', r.restriction_mode, 'restriction_markets', to_jsonb(r.restriction_markets))
                     from pipeline.provider_representation r
                    where r.provider_id = p_provider
                      and (r.effective_to is null or r.effective_to >= (now() at time zone 'Australia/Melbourne')::date)),  -- fixed: the platform's day is Melbourne's
                  jsonb_build_object('restriction_mode', null, 'restriction_markets', null))
$function$;
comment on function security.provider_restriction_v3_v1(uuid) is 'CF-247 s1015 (REQ-118): the provider market restriction for Website API v3 (restriction_mode, restriction_markets); nulls when no row is held or the agreement has ended.';
revoke all on function security.provider_restriction_v3_v1(uuid) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.website_v3_provider_item(p_item jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_provider uuid; v_campuses jsonb; v_page record; v_cc text;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' or not (p_item ? 'campuses') then return p_item; end if;
  select p.id, (select c.iso_alpha2 from ref.countries c where c.id = p.country_id) into v_provider, v_cc from catalogue.providers p where p.stable_key = p_item->>'provider_id';
  if v_provider is null then return p_item; end if;
  with k as (
    select k.id, k.stable_key, k.name, k.city, k.postcode, k.subdivision_id, k.country_id, k.is_primary, k.primary_basis
      from catalogue.campuses k
     where k.provider_id = v_provider and nullif(btrim(k.city), '') is not null and coalesce(k.status, 'active') <> 'inactive'),
  n as (
    -- one grouped read per provider, never one per campus
    select cc.campus_id, count(distinct cc.course_id) n
      from search.course_documents d
      join catalogue.course_campuses cc on cc.course_id = d.course_id
     where d.provider_id = v_provider
       -- checked per course: an anti-join builds the whole view on every call (measured 12 Nov 2026: 50 providers 2.3 s, per course 0.15 s)
       and (select count(*) from security.layer4_search_blocked_courses b where b.course_id = cc.course_id) = 0
     group by cc.campus_id)
  select coalesce(jsonb_agg(jsonb_build_object('city', security.place_presentable(k.city), 'postcode', k.postcode, 'subdivision_code', s.code,
           'metro_area', rc.metro_area, 'regional_category', rc.category, 'regional_category_name', rc.category_name,
           'campus_id', k.stable_key, 'campus_name', nullif(btrim(k.name), ''), 'course_count', coalesce(n.n, 0),
           'is_primary', coalesce(k.is_primary, false), 'primary_basis', k.primary_basis,  -- 20261119042000 (PR D)
           -- G-5 (17 Nov 2026): the approved locality the campus postcode maps to; null until it has a primary match
           'locality', security.destination_locality_for_postcode_v1(coalesce((select c.iso_alpha2 from ref.countries c where c.id = k.country_id), v_cc), k.postcode))
           order by lower(nullif(btrim(k.name), '')) nulls last, k.stable_key), '[]'::jsonb)
    into v_campuses
    from k
    left join ref.subdivisions s on s.id = k.subdivision_id
    left join pipeline.campus_regional_class rc on rc.campus_id = k.id
    left join n on n.campus_id = k.id;
  -- R31: the scholarships listing page the platform reads for this provider, and when it was last read
  select lp.url, lp.read_at into v_page
    from pipeline.scholarship_listing_pages lp
   where lp.provider_id = v_provider and lp.active and lp.status = 'read' and lp.read_at is not null
   order by lp.read_at desc, lp.id limit 1;
  return jsonb_set(p_item, '{campuses}', v_campuses)
         || jsonb_build_object('scholarships_page_url', v_page.url, 'scholarships_last_reviewed_at', v_page.read_at,
                               'accreditations', security.provider_accreditations_v3_v1(v_provider),  -- 18 Nov 2026 (REQ-57)
                               'accreditation_crown', security.provider_accreditation_crown_v1(v_provider))  -- s798 B1
         || security.provider_restriction_v3_v1(v_provider);  -- s1015 (REQ-118)
end $function$;

do $post$
declare v_api jsonb := security.consumer_api_check_v1(); v_item jsonb;
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1015_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1015_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  select public.website_v3_provider_item(jsonb_build_object('provider_id', p.stable_key, 'campuses', '[]'::jsonb)) into v_item
    from catalogue.providers p where p.stable_key is not null order by p.stable_key limit 1;
  if not (v_item ? 'restriction_mode' and v_item ? 'restriction_markets' and v_item ? 'accreditation_crown' and v_item ? 'scholarships_page_url') then
    raise exception 'post-check: the v3 provider item is missing a key: %', v_item;
  end if;
  if has_function_privilege('anon', 'security.provider_restriction_v3_v1(uuid)', 'execute') then raise exception 'post-check: anon can call the restriction helper'; end if;
end $post$;
