-- CF-247: "University group" filter and display in the admin console (follows 20260929170000_cf247_university_groups.sql).
-- Filter value is the short group code without the country prefix: go8, atn, iru, run ('au_go8' is also accepted).
-- Every replaced function is checksum-guarded against the live definition reviewed on 29 Sep 2026 and patched in place
-- with anchors that must match exactly once. Callers that do not pass university_group keep their existing behaviour.
--   public.ui_courses_decision_page(21 args)            6ff62cea57316381b0bd325b14ca9f74  -> new trailing p_university_group text default null
--   security.admin_providers_page(9 args)               ba36984a18ac8cef171bfa145021865a  -> new trailing p_university_group text default null
--   security.admin_course_page_fast(jsonb)              bebe5d0052f67ae4e54e631c9c6c5196
--   security.admin_course_page_fast_base(jsonb)         0d15eecf6399220f49b10cb9498458c5
--   security.admin_course_page_unfiltered_fast(jsonb)   22fc87ea9a658132727cbf5297e4c010
--   security.admin_catalogue_page(text,jsonb)           4c4de487258a12b0792ac5261c8f165e
--   security.admin_catalogue_filter_page(jsonb)         10ed9613c23426205bacd4db06f1b785
--   security.admin_provider_detail(uuid)                59ce87e80cd8d3a84b1304be7844bc21

-- Member providers of one university group (active membership, active group). Unknown code -> no rows.
create or replace function security.university_group_provider_ids(p_group text)
returns setof uuid language sql stable security definer set search_path to 'pg_catalog','catalogue','ref' as $f$
  select distinct m.provider_id
    from catalogue.provider_collection_memberships m
    join ref.institution_collections ic on ic.id=m.collection_id
   where ic.collection_type='university_group' and ic.status='active'
     and m.status='active' and (m.valid_to is null or m.valid_to>=current_date)
     and replace(ic.code,'au_','')=regexp_replace(lower(btrim(coalesce(p_group,''))),'^au_','')
$f$;
revoke all on function security.university_group_provider_ids(text) from public;
do $g$ begin
  if exists(select 1 from pg_roles where rolname='anon') then execute 'revoke all on function security.university_group_provider_ids(text) from anon'; end if;
  if exists(select 1 from pg_roles where rolname='authenticated') then execute 'revoke all on function security.university_group_provider_ids(text) from authenticated'; end if;
end $g$;
grant execute on function security.university_group_provider_ids(text) to service_role;

-- anchor-checked replace: the anchor must occur exactly once
create or replace function pg_temp.cf_patch(v text, a text, b text, label text) returns text language plpgsql as $f$
begin
  if position(a in v)=0 or (length(v)-length(replace(v,a,'')))/length(a)<>1 then
    raise exception 'anchor not found exactly once: %',label; end if;
  return replace(v,a,b);
end $f$;

do $patch$
declare v text; v_acl text;
  c_group_pred constant text := 'security.university_group_provider_ids(';
begin
  -- guards first: nothing is replaced unless every live definition matches the reviewed one
  if (select md5(prosrc) from pg_proc where oid='public.ui_courses_decision_page(integer,integer,text,text,text,uuid,text,text,text,text,text,boolean,boolean,boolean,boolean,numeric,text,text,text,boolean,boolean)'::regprocedure)<>'6ff62cea57316381b0bd325b14ca9f74' then
    raise exception 'ui_courses_decision_page changed since review; not replaced'; end if;
  if (select md5(prosrc) from pg_proc where oid='security.admin_providers_page(integer,integer,text,text,text,text,text,text,text)'::regprocedure)<>'ba36984a18ac8cef171bfa145021865a' then
    raise exception 'admin_providers_page changed since review; not replaced'; end if;
  if (select md5(prosrc) from pg_proc where oid='security.admin_course_page_fast(jsonb)'::regprocedure)<>'bebe5d0052f67ae4e54e631c9c6c5196' then
    raise exception 'admin_course_page_fast changed since review; not replaced'; end if;
  if (select md5(prosrc) from pg_proc where oid='security.admin_course_page_fast_base(jsonb)'::regprocedure)<>'0d15eecf6399220f49b10cb9498458c5' then
    raise exception 'admin_course_page_fast_base changed since review; not replaced'; end if;
  if (select md5(prosrc) from pg_proc where oid='security.admin_course_page_unfiltered_fast(jsonb)'::regprocedure)<>'22fc87ea9a658132727cbf5297e4c010' then
    raise exception 'admin_course_page_unfiltered_fast changed since review; not replaced'; end if;
  if (select md5(prosrc) from pg_proc where oid='security.admin_catalogue_page(text,jsonb)'::regprocedure)<>'4c4de487258a12b0792ac5261c8f165e' then
    raise exception 'admin_catalogue_page changed since review; not replaced'; end if;
  if (select md5(prosrc) from pg_proc where oid='security.admin_catalogue_filter_page(jsonb)'::regprocedure)<>'10ed9613c23426205bacd4db06f1b785' then
    raise exception 'admin_catalogue_filter_page changed since review; not replaced'; end if;
  if (select md5(prosrc) from pg_proc where oid='security.admin_provider_detail(uuid)'::regprocedure)<>'59ce87e80cd8d3a84b1304be7844bc21' then
    raise exception 'admin_provider_detail changed since review; not replaced'; end if;

  -- 1. public.ui_courses_decision_page: trailing p_university_group (default null keeps every 21-argument caller working)
  select proacl::text into v_acl from pg_proc where oid='public.ui_courses_decision_page(integer,integer,text,text,text,uuid,text,text,text,text,text,boolean,boolean,boolean,boolean,numeric,text,text,text,boolean,boolean)'::regprocedure;
  v:=pg_get_functiondef('public.ui_courses_decision_page(integer,integer,text,text,text,uuid,text,text,text,text,text,boolean,boolean,boolean,boolean,numeric,text,text,text,boolean,boolean)'::regprocedure);
  v:=pg_temp.cf_patch(v,$o$p_has_link boolean DEFAULT NULL::boolean)
 RETURNS jsonb$o$,$n$p_has_link boolean DEFAULT NULL::boolean, p_university_group text DEFAULT NULL::text)
 RETURNS jsonb$n$,'ui_courses_decision_page header');
  v:=pg_temp.cf_patch(v,$o$        and (p_provider_id is null or c.provider_id=p_provider_id)
$o$,$n$        and (p_provider_id is null or c.provider_id=p_provider_id)
        and (nullif(trim(coalesce(p_university_group,'')),'') is null or c.provider_id in (select security.university_group_provider_ids(p_university_group)))
$n$,'ui_courses_decision_page provider filter');
  v:=pg_temp.cf_patch(v,$o$'items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb)$o$,
                        $n$'items',coalesce(jsonb_agg((to_jsonb(o)-'total_count')||jsonb_build_object('university_groups',security.provider_university_groups(o.provider_id))),'[]'::jsonb)$n$,'ui_courses_decision_page items');
  drop function public.ui_courses_decision_page(integer,integer,text,text,text,uuid,text,text,text,text,text,boolean,boolean,boolean,boolean,numeric,text,text,text,boolean,boolean);
  execute v;
  execute 'revoke all on function public.ui_courses_decision_page(integer,integer,text,text,text,uuid,text,text,text,text,text,boolean,boolean,boolean,boolean,numeric,text,text,text,boolean,boolean,text) from public, anon, authenticated';
  execute 'grant execute on function public.ui_courses_decision_page(integer,integer,text,text,text,uuid,text,text,text,text,text,boolean,boolean,boolean,boolean,numeric,text,text,text,boolean,boolean,text) to service_role';
  if (select proacl::text from pg_proc where oid='public.ui_courses_decision_page(integer,integer,text,text,text,uuid,text,text,text,text,text,boolean,boolean,boolean,boolean,numeric,text,text,text,boolean,boolean,text)'::regprocedure)<>v_acl then
    raise exception 'ui_courses_decision_page privileges differ from the replaced function'; end if;

  -- 2. security.admin_providers_page: trailing p_university_group, groups on each item
  select proacl::text into v_acl from pg_proc where oid='security.admin_providers_page(integer,integer,text,text,text,text,text,text,text)'::regprocedure;
  v:=pg_get_functiondef('security.admin_providers_page(integer,integer,text,text,text,text,text,text,text)'::regprocedure);
  v:=pg_temp.cf_patch(v,$o$p_direction text DEFAULT 'asc'::text)
 RETURNS jsonb$o$,$n$p_direction text DEFAULT 'asc'::text, p_university_group text DEFAULT NULL::text)
 RETURNS jsonb$n$,'admin_providers_page header');
  v:=pg_temp.cf_patch(v,$o$        and (nullif(trim(coalesce(p_publication_status,'')),'') is null or p.publication_status=trim(p_publication_status))
$o$,$n$        and (nullif(trim(coalesce(p_publication_status,'')),'') is null or p.publication_status=trim(p_publication_status))
        and (nullif(trim(coalesce(p_university_group,'')),'') is null or p.id in (select security.university_group_provider_ids(p_university_group)))
$n$,'admin_providers_page filter');
  v:=pg_temp.cf_patch(v,$o$'items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),$o$,
                        $n$'items',coalesce(jsonb_agg((to_jsonb(o)-'total_count')||jsonb_build_object('university_groups',security.provider_university_groups(o.id))),'[]'::jsonb),$n$,'admin_providers_page items');
  drop function security.admin_providers_page(integer,integer,text,text,text,text,text,text,text);
  execute v;
  execute 'revoke all on function security.admin_providers_page(integer,integer,text,text,text,text,text,text,text,text) from public, anon, authenticated';
  execute 'grant execute on function security.admin_providers_page(integer,integer,text,text,text,text,text,text,text,text) to service_role';
  if (select proacl::text from pg_proc where oid='security.admin_providers_page(integer,integer,text,text,text,text,text,text,text,text)'::regprocedure)<>v_acl then
    raise exception 'admin_providers_page privileges differ from the replaced function'; end if;

  -- 3. security.admin_course_page_fast: a university_group filter leaves the unfiltered shortcut
  v:=pg_get_functiondef('security.admin_course_page_fast(jsonb)'::regprocedure);
  v:=pg_temp.cf_patch(v,$o$    and nullif(p_args->>'freshness','') is null
$o$,$n$    and nullif(p_args->>'freshness','') is null
    and nullif(p_args->>'university_group','') is null
$n$,'admin_course_page_fast simple check');
  execute v;

  -- 4. security.admin_course_page_fast_base: filter in the fast path, pass through on the legacy fee/completeness sort
  v:=pg_get_functiondef('security.admin_course_page_fast_base(jsonb)'::regprocedure);
  v:=pg_temp.cf_patch(v,$o$  v_min_completeness numeric:=nullif(p_args->>'min_completeness','')::numeric;
$o$,$n$  v_min_completeness numeric:=nullif(p_args->>'min_completeness','')::numeric;
  v_group text:=nullif(trim(coalesce(p_args->>'university_group','')),'');
$n$,'admin_course_page_fast_base declare');
  v:=pg_temp.cf_patch(v,$o$      v_sort,v_dir,v_has_state,v_has_link
    ));$o$,$n$      v_sort,v_dir,v_has_state,v_has_link,v_group
    ));$n$,'admin_course_page_fast_base legacy call');
  v:=pg_temp.cf_patch(v,$o$      and (v_provider_id is null or c.provider_id=v_provider_id)
$o$,$n$      and (v_provider_id is null or c.provider_id=v_provider_id)
      and (v_group is null or c.provider_id in (select security.university_group_provider_ids(v_group)))
$n$,'admin_course_page_fast_base filter');
  v:=pg_temp.cf_patch(v,$o$d.has_scholarship search_has_scholarship,
      pg.total_count$o$,$n$d.has_scholarship search_has_scholarship,
      security.provider_university_groups(pg.provider_id) university_groups,
      pg.total_count$n$,'admin_course_page_fast_base items');
  execute v;

  -- 5. security.admin_course_page_unfiltered_fast: groups on each item
  v:=pg_get_functiondef('security.admin_course_page_unfiltered_fast(jsonb)'::regprocedure);
  v:=pg_temp.cf_patch(v,$o$search_has_scholarship
    from paged pg$o$,$n$search_has_scholarship,
      security.provider_university_groups(pg.provider_id) university_groups
    from paged pg$n$,'admin_course_page_unfiltered_fast items');
  execute v;

  -- 6. security.admin_catalogue_page: pass the filter to both page functions
  v:=pg_get_functiondef('security.admin_catalogue_page(text,jsonb)'::regprocedure);
  v:=pg_temp.cf_patch(v,$o$coalesce(nullif(p_args->>'sort',''),'provider'),v_dir);$o$,
                        $n$coalesce(nullif(p_args->>'sort',''),'provider'),v_dir,nullif(p_args->>'university_group',''));$n$,'admin_catalogue_page providers_page');
  v:=pg_temp.cf_patch(v,$o$v_dir,v_has_state,v_has_link);$o$,
                        $n$v_dir,v_has_state,v_has_link,nullif(p_args->>'university_group',''));$n$,'admin_catalogue_page courses_page');
  execute v;

  -- 7. security.admin_catalogue_filter_page: filter kind 'university_group'
  v:=pg_get_functiondef('security.admin_catalogue_filter_page(jsonb)'::regprocedure);
  v:=pg_temp.cf_patch(v,$o$  else
    raise exception 'unsupported catalogue filter kind: %'$o$,$n$  elsif v_kind='university_group' then
    with q as (
      select replace(ic.code,'au_','') value,ic.name label,
             (select count(*)::int from security.university_group_provider_ids(ic.code) g) provider_count,
             (select count(*)::int from catalogue.courses c where c.provider_id in (select security.university_group_provider_ids(ic.code))) course_count
      from ref.institution_collections ic
      join ref.countries co on co.id=ic.country_id
      where ic.collection_type='university_group' and ic.status='active'
        and (v_country is null or co.iso_alpha2::text=v_country)
        and (v_query is null or lower(ic.name||' '||replace(ic.code,'au_','')) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,
                       'meta',provider_count||case when provider_count=1 then ' university' else ' universities' end,
                       'count',course_count,'course_count',course_count,'provider_count',provider_count) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  else
    raise exception 'unsupported catalogue filter kind: %'$n$,'admin_catalogue_filter_page kinds');
  execute v;

  -- 8. security.admin_provider_detail: university groups (additive)
  v:=pg_get_functiondef('security.admin_provider_detail(uuid)'::regprocedure);
  v:=pg_temp.cf_patch(v,$o$    'scholarship_count',(select count(*) from scholarship.scholarships s where s.provider_id=p_provider_id),
$o$,$n$    'scholarship_count',(select count(*) from scholarship.scholarships s where s.provider_id=p_provider_id),
    'university_groups',security.provider_university_groups(p_provider_id),
$n$,'admin_provider_detail groups');
  execute v;

  -- post-checks: exactly one version of each replaced page function remains
  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='ui_courses_decision_page')<>1 then
    raise exception 'expected one ui_courses_decision_page'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='security' and p.proname='admin_providers_page')<>1 then
    raise exception 'expected one admin_providers_page'; end if;
  if position(c_group_pred in pg_get_functiondef('security.admin_course_page_fast_base(jsonb)'::regprocedure))=0 then
    raise exception 'fast path filter missing after patch'; end if;
end $patch$;
