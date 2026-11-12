-- CF-247 Website API v3, build brief WP-1.4 (R31, REQ-46: scholarships page link and last reviewed date per provider) and WP-1.7 (O26, REQ-61:
-- description excerpt on search items). Decision 277: v3 only; v2 is only read.
--   R31  provider (providers, provider, sync provider items): scholarships_page_url = the provider's scholarships listing page the platform reads
--        (pipeline.scholarship_listing_pages, active and read; the most recently read when there are several); scholarships_last_reviewed_at =
--        when it was last read. Both null when no listing page is read for the provider (live 12 Nov 2026: 13 of the 67 providers with
--        published scholarships). Null means not held.
--   O26  search items: description_excerpt = the course description (the same text as course detail description) cut to its first
--        240 characters at a whole word, with "…" when cut; null when no description is held.
-- Replaces: public.website_v3_provider_item(jsonb), public.website_v3_course_search(jsonb, integer, integer, text) (same names and signatures;
--   md5-guarded against the WP-1.1 and WP-0 definitions). Retires: nothing.

do $guard$
begin
  if md5(pg_get_functiondef('public.website_v3_provider_item(jsonb)'::regprocedure)) <> '0e81bf4d1b3984a42222936d478c6606' then
    raise exception 'live public.website_v3_provider_item differs from the WP-1.1 definition (md5 %)', md5(pg_get_functiondef('public.website_v3_provider_item(jsonb)'::regprocedure));
  end if;
  if md5(pg_get_functiondef('public.website_v3_course_search(jsonb,integer,integer,text)'::regprocedure)) <> '38f89a7e4d78b8b86724060accced2e7' then
    raise exception 'live public.website_v3_course_search differs from the WP-0 definition (md5 %)', md5(pg_get_functiondef('public.website_v3_course_search(jsonb,integer,integer,text)'::regprocedure));
  end if;
end $guard$;

-- R23 (WP-1.1, unchanged) and R31 (WP-1.4)
create or replace function public.website_v3_provider_item(p_item jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_provider uuid; v_campuses jsonb; v_page record;
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
  -- R31: the scholarships listing page the platform reads for this provider, and when it was last read
  select lp.url, lp.read_at into v_page
    from pipeline.scholarship_listing_pages lp
   where lp.provider_id = v_provider and lp.active and lp.status = 'read' and lp.read_at is not null
   order by lp.read_at desc, lp.id limit 1;
  return jsonb_set(p_item, '{campuses}', v_campuses)
         || jsonb_build_object('scholarships_page_url', v_page.url, 'scholarships_last_reviewed_at', v_page.read_at);
end $$;
comment on function public.website_v3_provider_item(jsonb) is
  'Website API v3: a v2 provider item with campuses[] one per campus (R23) and scholarships_page_url, scholarships_last_reviewed_at (R31); nothing else changed.';

-- O26 (WP-1.7): a search item with R28 and description_excerpt
create or replace function public.website_v3_course_search_item(p_item jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v3_course_item_r28(p_item); v_desc text;
begin
  if v is null or jsonb_typeof(v) <> 'object' then return v; end if;
  select nullif(btrim(d.description), '') into v_desc from search.course_documents d
   where lower(d.course_stable_key) = lower(v->>'course_id') and d.course_stable_key is not null limit 1;
  if v_desc is not null and length(v_desc) > 240 then  -- fixed: API contract (build brief WP-1.7: first 240 characters, whole words)
    v_desc := coalesce(nullif(regexp_replace(left(v_desc, 240), '\s+\S*$', ''), ''), left(v_desc, 240)) || '…';  -- fixed: as above
  end if;
  return v || jsonb_build_object('description_excerpt', v_desc);
end $$;
comment on function public.website_v3_course_search_item(jsonb) is
  'Website API v3: a v2 search item with intakes[].start_date_status (R28) and description_excerpt (O26, first 240 characters at a whole word).';

create or replace function public.website_v3_course_search(p_filters jsonb, p_page integer, p_page_size integer, p_sort text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v2_course_search(p_filters, p_page, p_page_size, p_sort);
begin
  if jsonb_typeof(v->'items') = 'array' then
    v := jsonb_set(v, '{items}', (select coalesce(jsonb_agg(public.website_v3_course_search_item(x) order by o), '[]'::jsonb)
                                    from jsonb_array_elements(v->'items') with ordinality t(x, o)));
  end if;
  return v;
end $$;
comment on function public.website_v3_course_search(jsonb, integer, integer, text) is
  'Website API v3 (Decision 277): website_v2_course_search with intakes[].start_date_status (R28) and description_excerpt (O26).';

revoke all on function public.website_v3_course_search_item(jsonb) from public, anon, authenticated;
grant execute on function public.website_v3_course_search_item(jsonb) to service_role;

do $post$ begin
  if not (public.website_v3_course_search_item('{"course_id":"none","intakes":[]}'::jsonb) ? 'description_excerpt') then raise exception 'post-check: search items carry description_excerpt'; end if;
end $post$;
