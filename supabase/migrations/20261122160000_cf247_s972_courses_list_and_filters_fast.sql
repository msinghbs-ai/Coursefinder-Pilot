-- CF-247 s972 (session S1-API-Frontend-Delivery, consolidated batch Part 2; Platform Admin 22 Nov 2026 14:22 AEDT): REQ-105, the Courses page
-- opens in under a second.
-- Measured live 22 Nov 2026 (rolled-back dry runs, signed in as a Platform Admin): the first Courses read, admin_read('courses_page') with
-- the default Active filter, took 1.3 to 5.0 s; the filter lists took 0.1 to 3.9 s each when opened (Region 1.0 to 3.9 s, Delivery 0.5 to 1.5 s).
-- 1. The default list (Active, course order, no other filter) now takes the page-first path that the unfiltered list already used:
--    security.admin_course_page_unfiltered_fast reads the Active filter, and security.admin_course_page_fast sends Active there
--    (md5-guarded edits). A partial index holds the Active courses in title order. Same rows, order, values and total as before
--    (compared live on four pages, including the last). The page-first path also returns the three columns it had left out
--    (open_to_international, open_to_domestic, intl_fee_basis), so the All view carries them too.
-- 2. security.admin_catalogue_filter_page (Country, Region, Provider, Study level, Field of study, Delivery mode) reads the providers of the
--    country and the courses of the region once, and each list is a semi-join over its own small reference table; the delivery modes are
--    read from two new indexes (one probe per mode). Same values, labels, order, totals and empty-list notes as before (compared live over
--    every country, region, search and page). The lists read the catalogue as it is at that moment, so there is nothing to invalidate.
-- 3. Two partial indexes let the list's Published column read each course's website and Zoho feed changes by course id.
-- Consumer API untouched (G3 checked before and after: indexes only, no column changed). Live on deploy. $0.
-- G1: no new job. G2: no operational value. Locks unchanged.
-- Parity: live head 20261122150000 (s971) read 22 Nov 2026 15:40 AEDT; this file is numbered strictly above it.
-- Replaces: the per-row filter-list reads in security.admin_catalogue_filter_page (rewritten in place); the course-first path for the default Active list.
-- Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s972_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s972_cron on commit drop as select count(*) n from cron.job where active;

-- Indexes (reads only; no column changes). Each is built inside a short lock retry: a busy writer can hold a table for a few
-- seconds, and the pipeline is never queued behind this change for long.
do $i$
declare v_sql text; v_try int;
begin
  foreach v_sql in array array[
    'create index if not exists courses_active_title_idx on catalogue.courses (lower(canonical_title), id) where lifecycle_status = ''active''',
    'create index if not exists courses_delivery_mode_norm_idx on catalogue.courses ((nullif(btrim(delivery_mode), '''')), provider_id)',
    'create index if not exists course_campuses_delivery_mode_idx on catalogue.course_campuses (delivery_mode)',
    -- the list's Published column reads each course's last website and Zoho feed change by course id
    'create index if not exists website_sync_items_course_ref_idx on pipeline.website_sync_items (ref_id) where entity = ''course''',
    'create index if not exists zoho_sync_items_course_ref_idx on pipeline.zoho_sync_items (ref_id) where entity = ''course''',
    'analyze catalogue.courses', 'analyze catalogue.course_campuses', 'analyze pipeline.website_sync_items', 'analyze pipeline.zoho_sync_items']
  loop
    for v_try in 1 .. 10 loop  -- fixed: lock retry count for a busy table
      begin
        perform set_config('lock_timeout', '3s', true);  -- fixed: lock wait per try
        execute v_sql;
        exit;
      exception when lock_not_available then
        if v_try = 10 then raise; end if;
        perform pg_sleep(2);  -- fixed: pause between lock tries
      end;
    end loop;
  end loop;
  perform set_config('lock_timeout', '5s', true);  -- fixed: back to this change's lock wait
end $i$;

-- regex edits of the live definition, guarded by its md5 before; each edit must apply exactly once
create or replace function pg_temp.edit_re(p_sig text, p_before text, p_after text, p_edits text[][]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_new text;
begin
  if p_after is not null and md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (select count(*) from regexp_matches(v_def, p_edits[i][1], 'g')) <> 1 then
      raise exception '%: edit % must apply exactly once (found %)', p_sig, i, (select count(*) from regexp_matches(v_def, p_edits[i][1], 'g'));
    end if;
    v_def := regexp_replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
  if p_after is not null and md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied ' || md5(pg_get_functiondef(p_sig::regprocedure));
end $f$;

select pg_temp.edit_re('security.admin_course_page_unfiltered_fast(jsonb)', '93350f637166fa616b3f4ad7187205e9', '74a49322d1c91ac35bf0e3f0db5581ac', array[
    array['  v_result jsonb;', E'  v_result jsonb;\n  -- 22 Nov 2026 (REQ-105, s972): the default Courses list (Active) is read in title order straight from its index\n  v_lifecycle text:=nullif(btrim(coalesce(p_args->>''lifecycle_status'','''')),'''');'],
    array['select count\(\*\) into v_total from catalogue\.courses;', 'select count(*) into v_total from catalogue.courses c where (v_lifecycle is null or c.lifecycle_status=v_lifecycle);'],
    array[E'    order by lower\\(c\\.canonical_title\\),c\\.id\n', E'    where (v_lifecycle is null or c.lifecycle_status=v_lifecycle)\n    order by lower(c.canonical_title),c.id\n'],
    array['c\.duration_value,c\.description,c\.delivery_mode canonical_delivery_mode,', 'c.duration_value,c.description,c.delivery_mode canonical_delivery_mode,c.open_to_international,c.open_to_domestic,'],
    array['      coalesce\(ssc\.identifier,pg\.course_code\) display_code', '      pg.open_to_international,pg.open_to_domestic,coalesce(ssc.identifier,pg.course_code) display_code'],
    array['select cf\.amount, cf\.currency_code, cf\.fee_year from catalogue\.course_fees', 'select cf.amount, cf.currency_code, cf.fee_year, cf.basis from catalogue.course_fees'],
    array['ifee\.fee_year intl_fee_year,', 'ifee.fee_year intl_fee_year,ifee.basis intl_fee_basis,']]);
select pg_temp.edit_re('security.admin_course_page_fast(jsonb)', '0018ad72937c324750888ad37385a42a', '0df468929bc1f30b769496a0d7be109c', array[
  array['and nullif\(p_args->>''lifecycle_status'',''''\) is null', 'and coalesce(nullif(p_args->>''lifecycle_status'',''''),''active'')=''active''']]);

-- The filter lists: replaced only from the definition this change was written against
do $m$
begin
  if md5(pg_get_functiondef('security.admin_catalogue_filter_page(jsonb)'::regprocedure)) <> '50c21dce0dbdfb23d3c49030f21d8056' then
    raise exception 'live security.admin_catalogue_filter_page differs from the definition this change replaces (md5 %)', md5(pg_get_functiondef('security.admin_catalogue_filter_page(jsonb)'::regprocedure));
  end if;
end $m$;
CREATE OR REPLACE FUNCTION security.admin_catalogue_filter_page(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_kind text:=lower(nullif(trim(coalesce(p_args->>'filter_kind','')),''));
  v_query text:=lower(nullif(trim(coalesce(p_args->>'query','')),''));
  v_country text:=upper(nullif(trim(coalesce(p_args->>'country_code','')),''));
  v_subdivision text:=upper(nullif(trim(coalesce(p_args->>'subdivision_code','')),''));
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,10),1),case when lower(nullif(trim(coalesce(p_args->>'filter_kind','')),''))='level' then 100 else 10 end);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_items jsonb:='[]'::jsonb;
  v_total integer:=0;
  v_sub_id uuid;
  v_empty text;
  v_pids uuid[];
  v_cids uuid[];
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  if v_subdivision is not null then select sd.id into v_sub_id from ref.subdivisions sd where sd.code=v_subdivision; end if;

  -- 22 Nov 2026 (REQ-105, s972): the filter lists read the providers of the country and the courses of the region once,
  -- then each list is a semi-join over its own small reference table. Same values, labels, order and totals as before.
  if v_country is not null and v_kind not in ('university_group','country') then
    select coalesce(array_agg(p.id),'{}'::uuid[]) into v_pids from catalogue.providers p join ref.countries co on co.id=p.country_id where co.iso_alpha2::text=v_country;
  end if;
  if v_subdivision is not null and v_kind in ('provider','level','field','delivery') then
    select coalesce(array_agg(distinct x.id),'{}'::uuid[]) into v_cids from (
      select cc.course_id id from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id
      where cp.subdivision_id in (select sd.id from ref.subdivisions sd where sd.code=v_subdivision)
      union all
      select c.id from catalogue.courses c join catalogue.providers p on p.id=c.provider_id
      where p.subdivision_id=v_sub_id and not exists(select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id
                                                     where cc.course_id=c.id and cp.subdivision_id is not null)) x;
  end if;

  if v_kind='country' then
    with q as (
      select distinct co.iso_alpha2::text value,co.name label,co.iso_alpha2::text meta
      from ref.countries co
      where co.id in (select p.country_id from catalogue.providers p where exists(select 1 from catalogue.courses c where c.provider_id=p.id))
        and (v_query is null or lower(co.name||' '||co.iso_alpha2::text) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='subdivision' then
    with q as (
      select distinct s.code value,s.name label,s.code meta
      from ref.subdivisions s
      where (v_query is null or lower(s.name||' '||s.code) like '%'||v_query||'%')
        and (exists(select 1 from catalogue.campuses cp join catalogue.course_campuses cc on cc.campus_id=cp.id join catalogue.courses c on c.id=cc.course_id
                    where cp.subdivision_id=s.id and (v_pids is null or c.provider_id=any(v_pids)))
          or exists(select 1 from catalogue.providers p
                    where p.subdivision_id=s.id and (v_pids is null or p.id=any(v_pids))
                      and exists(select 1 from catalogue.courses c where c.provider_id=p.id
                                   and not exists(select 1 from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id
                                                  where cc.course_id=c.id and cp.subdivision_id is not null))))
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='provider' then
    with q as (
      select distinct p.id::text value,coalesce(p.display_name,p.canonical_name) label,p.stable_key meta
      from catalogue.providers p
      where (v_pids is null or p.id=any(v_pids))
        and exists(select 1 from catalogue.courses c where c.provider_id=p.id and (v_cids is null or c.id=any(v_cids)))
        and (v_query is null or lower(coalesce(p.display_name,p.canonical_name)||' '||coalesce(p.stable_key,'')) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='level' then
    with q as (
      select distinct sl.code value,sl.name label,coalesce(g.group_name,'Other') meta,sl.sort_order,coalesce(g.group_order,90) group_order
      from ref.study_levels sl
      left join ref.study_level_groups g on g.level_code=sl.code
      where exists(select 1 from catalogue.courses c where c.study_level_id=sl.id
                     and (v_pids is null or c.provider_id=any(v_pids)) and (v_cids is null or c.id=any(v_cids)))
        and (v_query is null or lower(sl.name||' '||sl.code) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select value,label,meta,group_order,sort_order from q order by group_order,sort_order,lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta,'group',meta,'group_order',group_order) order by group_order,sort_order,lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='field' then
    with q as (
      select distinct fos.code value,fos.name label,fos.code meta
      from ref.fields_of_study fos
      where exists(select 1 from catalogue.courses c where c.primary_field_id=fos.id
                     and (v_pids is null or c.provider_id=any(v_pids)) and (v_cids is null or c.id=any(v_cids)))
        and (v_query is null or lower(fos.name||' '||fos.code) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;

  elsif v_kind='delivery' then
    -- the few delivery modes are read from their indexes (one probe per mode), then kept when a course in scope has the mode
    with recursive t(m) as (
      (select nullif(btrim(c.delivery_mode),'') from catalogue.courses c where nullif(btrim(c.delivery_mode),'') is not null order by 1 limit 1)
      union all
      select (select nullif(btrim(c.delivery_mode),'') from catalogue.courses c where nullif(btrim(c.delivery_mode),'')>t.m order by 1 limit 1) from t where t.m is not null
    ), u(m) as (
      (select cc.delivery_mode from catalogue.course_campuses cc where cc.delivery_mode is not null order by 1 limit 1)
      union all
      select (select cc.delivery_mode from catalogue.course_campuses cc where cc.delivery_mode>u.m order by 1 limit 1) from u where u.m is not null
    ), q as (
      select m value,upper(left(replace(m,'_',' '),1))||substr(replace(m,'_',' '),2) label,null::text meta
      from (
        select t.m from t where t.m is not null
          and exists(select 1 from catalogue.courses c where nullif(btrim(c.delivery_mode),'')=t.m
                       and (v_pids is null or c.provider_id=any(v_pids)) and (v_cids is null or c.id=any(v_cids)))
        union
        select u.m from u where u.m is not null
          and exists(select 1 from catalogue.course_campuses cc join catalogue.courses c on c.id=cc.course_id
                     where cc.delivery_mode=u.m and nullif(btrim(c.delivery_mode),'') is null
                       and (v_pids is null or c.provider_id=any(v_pids)) and (v_cids is null or c.id=any(v_cids)))
      ) x
      where m is not null and btrim(m)<>''
        and (v_query is null or lower(replace(m,'_',' ')) like '%'||v_query||'%')
    ), n as (select count(*) total from q),
    page as (select * from q order by lower(label),value limit v_limit offset v_offset)
    select coalesce((select jsonb_agg(jsonb_build_object('value',value,'label',label,'meta',meta) order by lower(label),value) from page),'[]'::jsonb),
           coalesce((select total from n),0)
      into v_items,v_total;
  elsif v_kind='university_group' then
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
    raise exception 'unsupported catalogue filter kind: %',coalesce(v_kind,'') using errcode='22023';
  end if;

  if v_total=0 and v_query is null then
    v_empty:=case v_kind
      when 'university_group' then 'No university groups are set up for this country.'
      when 'field' then 'Field of study is not classified for this country yet.'
      when 'subdivision' then 'No regions are recorded for this country.'
      when 'delivery' then 'No delivery mode is recorded for these courses.'
      else null end;
  end if;
  return jsonb_build_object(
    'items',v_items,'total',v_total,'limit',v_limit,'offset',v_offset,
    'has_more',(v_offset+jsonb_array_length(v_items))<v_total
  )||case when v_empty is null then '{}'::jsonb else jsonb_build_object('empty_reason',v_empty) end;
end $function$
;

do $c$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if (select count(*) from pg_indexes where schemaname in ('catalogue', 'pipeline') and indexname in ('courses_active_title_idx', 'courses_delivery_mode_norm_idx', 'course_campuses_delivery_mode_idx', 'website_sync_items_course_ref_idx', 'zoho_sync_items_course_ref_idx')) <> 5 then raise exception 'post-check: an index is missing'; end if;
  if position('v_lifecycle' in pg_get_functiondef('security.admin_course_page_unfiltered_fast(jsonb)'::regprocedure)) = 0 then raise exception 'post-check: the Active list path is missing'; end if;
  if position('v_pids' in pg_get_functiondef('security.admin_catalogue_filter_page(jsonb)'::regprocedure)) = 0 then raise exception 'post-check: the filter lists were not replaced'; end if;
  if (select count(*) from cron.job where active) <> (select n from s972_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s972_locks) then raise exception 'post-check: the manual locks changed'; end if;
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
