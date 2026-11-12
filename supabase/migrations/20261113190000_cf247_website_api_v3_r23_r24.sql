-- CF-247 Website API v3, build brief WP-1.1 (R23 campus names and course counts) and WP-1.2 (R24 nationality eligibility status).
-- Decision 277 (Platform Admin 12 Nov 2026 21:00): new consumer fields go into Website API v3 only; v3 is open to additions until the website goes
-- live on it. Build brief (admin docs/integrations/api-v3/WEBSITE-API-V3-BUILD-BRIEF.md, Platform Admin 21:30): "Rebuild the R23 branch as
-- website_v3_*; do not merge it into v2" (D-5, Platform Admin 21:29: "proceed"). The rules are the ones approved for the 3 Nov developer request
-- (proposal docs/platform/nz-enrichment-brief/2026-11-03-website-api-v2-change-proposal.md sections 2 and 3), unchanged; only the home moves to v3.
--
--   R23  Provider campuses[] (providers, provider, sync provider items): one item per campus by its stable identity, never merged by city or
--        postcode. Each item keeps city, postcode, subdivision_code, metro_area, regional_category and regional_category_name and gains
--          campus_id     the campus's stable key
--          campus_name   the stored campus name (null when blank: not held)
--          course_count  distinct courses the API returns linked to this campus (search documents of this provider not held back by
--                        security.layer4_search_blocked_courses: the same rule as the provider's course_count, restricted to the campus)
--        Items are ordered by campus name (blank last), then campus_id. Course campuses[] is not changed (decision P3).
--   R24  Scholarship nationality_eligibility_status (scholarships, scholarship, sync scholarship items), the first that applies of
--          under_review  a pending Layer 4 item on who the scholarship is for (nationalities, nationality, citizenship_eligibility, audience,
--                        student_type), or a pending scholarship AI review whose reason is who it is for
--          restricted    citizenship_eligibility names a country or region code; or an active nationality / citizenship_and_residency criterion
--                        names codes; or student_type is domestic
--          unrestricted  no code is held and the nationality reading holds an explicit "any nationality" phrase (key ANY)
--          unknown       otherwise. An empty list is never read as unrestricted.
--
-- v2 is not touched: every public.website_v2_*, api.* and consumer table is only read (G3, s57). The v3 wrappers of WP-0.2 (migration
-- 20261113180000) are replaced, md5-guarded against their live definitions.
-- Replaces: public.website_v3_providers, public.website_v3_provider (both forms), public.website_v3_scholarships, public.website_v3_scholarship,
--   public.website_v3_sync (same names and signatures; WP-0.2 wrappers). Supersedes the unmerged v2 drafts on branches cf247-devapi-r23-r24 and
--   cf247-devapi-r23-r24-release (Pilot #945, #954), closed unmerged.
-- Retires: nothing.

-- the live WP-0.2 definitions this change replaces (a different live definition stops the migration)
do $guard$
declare v_want jsonb := jsonb_build_object(
  'public.website_v3_providers(jsonb,integer,integer,text)', '670ea0797f9a11e0f0110b9ae18e791c',
  'public.website_v3_provider(text)', '032b6affdd69f5d15720d3c215fc1d86',
  'public.website_v3_provider(text,text)', 'e9a91c1ea9d7f1bb4feec9f771802848',
  'public.website_v3_scholarships(jsonb,integer,integer)', 'd4a37a39624266b5dbd3175555998d25',
  'public.website_v3_scholarship(text)', 'e6637de22ec52aeceb79dd9e5b1a66c1',
  'public.website_v3_sync(text,boolean,text[],integer)', '798e96a4c96a7b3782df2d5b034e74be'); k text;
begin
  for k in select jsonb_object_keys(v_want) loop
    if md5(pg_get_functiondef(k::regprocedure)) <> v_want->>k then
      raise exception 'live % differs from the WP-0.2 definition this change replaces (md5 %)', k, md5(pg_get_functiondef(k::regprocedure));
    end if;
  end loop;
end $guard$;

-- R23: a v2 provider item with campuses[] one per campus
create or replace function public.website_v3_provider_item(p_item jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_provider uuid; v_campuses jsonb;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' or not (p_item ? 'campuses') then return p_item; end if;
  select p.id into v_provider from catalogue.providers p where p.stable_key = p_item->>'provider_id';
  if v_provider is null then return p_item; end if;
  with k as (
    select k.id, k.stable_key, k.name, k.city, k.postcode, k.subdivision_id
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
           'campus_id', k.stable_key, 'campus_name', nullif(btrim(k.name), ''), 'course_count', coalesce(n.n, 0))
           order by lower(nullif(btrim(k.name), '')) nulls last, k.stable_key), '[]'::jsonb)
    into v_campuses
    from k
    left join ref.subdivisions s on s.id = k.subdivision_id
    left join pipeline.campus_regional_class rc on rc.campus_id = k.id
    left join n on n.campus_id = k.id;
  return jsonb_set(p_item, '{campuses}', v_campuses);
end $$;
comment on function public.website_v3_provider_item(jsonb) is
  'Website API v3 R23 (build brief WP-1.1): a v2 provider item with campuses[] one per campus (campus_id, campus_name, course_count); nothing else changed.';

-- R24: a v2 scholarship item with nationality_eligibility_status
create or replace function public.website_v3_scholarship_item(p_item jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid; v_status text;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' or not (p_item ? 'scholarship_id') then return p_item; end if;
  select s.id into v_id from scholarship.scholarships s where s.stable_key = p_item->>'scholarship_id';
  if v_id is null then return p_item; end if;
  v_status := case
    when exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'scholarship' and r.entity_id = v_id and r.status = 'pending'
                   and r.field_code in ('nationalities', 'nationality', 'citizenship_eligibility', 'audience', 'student_type'))
      or exists (select 1 from pipeline.scholarship_ai_reviews a where a.scholarship_id = v_id and a.status = 'pending' and a.reason ~* 'who it is for')
      then 'under_review'
    when (jsonb_typeof(p_item->'citizenship_eligibility') = 'array' and jsonb_array_length(p_item->'citizenship_eligibility') > 0)
      or p_item->>'student_type' = 'domestic'
      or exists (select 1 from scholarship.criteria c where c.scholarship_id = v_id and coalesce(c.status, 'active') not in ('rejected', 'superseded', 'withdrawn')
                   and c.criterion_type in ('nationality', 'citizenship_and_residency') and cardinality(c.value_codes) > 0)
      then 'restricted'
    when exists (select 1 from scholarship.nationality_readings nr where nr.scholarship_id = v_id and cardinality(nr.codes) = 0 and nr.phrases ? 'ANY')
      then 'unrestricted'
    else 'unknown' end;
  return p_item || jsonb_build_object('nationality_eligibility_status', v_status);
end $$;
comment on function public.website_v3_scholarship_item(jsonb) is
  'Website API v3 R24 (build brief WP-1.2): a v2 scholarship item with nationality_eligibility_status; nothing else changed.';

-- the v3 actions: the v2 answer with the item functions applied
create or replace function public.website_v3_providers(p_filters jsonb, p_page integer, p_page_size integer, p_sort text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v2_providers(p_filters, p_page, p_page_size, p_sort);
begin
  if jsonb_typeof(v->'items') = 'array' then
    v := jsonb_set(v, '{items}', (select coalesce(jsonb_agg(public.website_v3_provider_item(x) order by o), '[]'::jsonb)
                                    from jsonb_array_elements(v->'items') with ordinality t(x, o)));
  end if;
  return v;
end $$;
create or replace function public.website_v3_provider(p_provider_id text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v2_provider(p_provider_id);
begin
  if jsonb_typeof(v->'item') = 'object' then v := jsonb_set(v, '{item}', public.website_v3_provider_item(v->'item')); end if;
  return v;
end $$;
create or replace function public.website_v3_provider(p_provider_id text, p_edu_country text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v2_provider(p_provider_id, p_edu_country);
begin
  if jsonb_typeof(v->'item') = 'object' then v := jsonb_set(v, '{item}', public.website_v3_provider_item(v->'item')); end if;
  return v;
end $$;
create or replace function public.website_v3_scholarships(p_filters jsonb, p_page integer, p_page_size integer)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v2_scholarships(p_filters, p_page, p_page_size);
begin
  if jsonb_typeof(v->'items') = 'array' then
    v := jsonb_set(v, '{items}', (select coalesce(jsonb_agg(public.website_v3_scholarship_item(x) order by o), '[]'::jsonb)
                                    from jsonb_array_elements(v->'items') with ordinality t(x, o)));
  end if;
  return v;
end $$;
create or replace function public.website_v3_scholarship(p_scholarship_id text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v2_scholarship(p_scholarship_id);
begin
  if jsonb_typeof(v->'item') = 'object' then v := jsonb_set(v, '{item}', public.website_v3_scholarship_item(v->'item')); end if;
  return v;
end $$;
create or replace function public.website_v3_sync(p_cursor text, p_full boolean, p_entities text[], p_page_size integer)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v jsonb := public.website_v2_sync(p_cursor, p_full, p_entities, p_page_size);
begin
  if jsonb_typeof(v->'items') = 'array' then
    v := jsonb_set(v, '{items}', (select coalesce(jsonb_agg(case when not (x ? 'item') or jsonb_typeof(x->'item') <> 'object' then x
                                                                  when x->>'entity' = 'course' then jsonb_set(x, '{item}', public.website_v3_course_item_r28(x->'item'))
                                                                  when x->>'entity' = 'provider' then jsonb_set(x, '{item}', public.website_v3_provider_item(x->'item'))
                                                                  when x->>'entity' = 'scholarship' then jsonb_set(x, '{item}', public.website_v3_scholarship_item(x->'item'))
                                                                  else x end order by o), '[]'::jsonb)
                                    from jsonb_array_elements(v->'items') with ordinality t(x, o)));
  end if;
  return v;
end $$;

comment on function public.website_v3_providers(jsonb, integer, integer, text) is 'Website API v3 (Decision 277): website_v2_providers with campuses[] one per campus (R23).';
comment on function public.website_v3_provider(text) is 'Website API v3 (Decision 277): website_v2_provider with campuses[] one per campus (R23).';
comment on function public.website_v3_provider(text, text) is 'Website API v3 (Decision 277): website_v2_provider with campuses[] one per campus (R23).';
comment on function public.website_v3_scholarships(jsonb, integer, integer) is 'Website API v3 (Decision 277): website_v2_scholarships with nationality_eligibility_status (R24).';
comment on function public.website_v3_scholarship(text) is 'Website API v3 (Decision 277): website_v2_scholarship with nationality_eligibility_status (R24).';
comment on function public.website_v3_sync(text, boolean, text[], integer) is 'Website API v3 (Decision 277): website_v2_sync with R28 on course items, R23 on provider items and R24 on scholarship items.';

revoke all on function public.website_v3_provider_item(jsonb) from public, anon, authenticated;
revoke all on function public.website_v3_scholarship_item(jsonb) from public, anon, authenticated;
grant execute on function public.website_v3_provider_item(jsonb) to service_role;
grant execute on function public.website_v3_scholarship_item(jsonb) to service_role;

do $post$ begin
  if public.website_v3_scholarship_item('{"scholarship_id":"none"}'::jsonb) ? 'nationality_eligibility_status' then raise exception 'post-check: an unknown scholarship must pass through unchanged'; end if;
  if public.website_v3_provider_item('{"provider_id":"none","campuses":[]}'::jsonb) <> '{"provider_id":"none","campuses":[]}'::jsonb then raise exception 'post-check: an unknown provider must pass through unchanged'; end if;
end $post$;
