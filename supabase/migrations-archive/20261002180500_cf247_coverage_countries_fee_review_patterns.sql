-- CF-247 (Decision 213, 2 Oct 2026). Platform Admin, 06:56 (screenshots): "Fix error, what is the course page pattern
-- doing? Fees schedule should have bulk action approvals, and review all entries. There is one which has nothing to
-- approve but still keeps appearing. There is no country or uni filter in completeness and coverage, it looks more AU
-- focussed." Answers (multiple choice): retire the course-page pattern requests; Coverage opens on All countries.
--
-- 1. Course-page pattern requests (CF-054 source patterns): 1,415 queued and 240 blocked since 31 Aug-25 Sep, bound to a
--    retired free model that is paused, so Run failed ("Edge Function returned a non-2xx status code"). The course-link
--    search (Decision 204) now finds course pages. They are cancelled (kept, with the reason); new ones are created
--    cancelled.
-- 2. Fee schedules: waiting documents are listed first and up to 300 are returned (was the newest 50).
-- 3. Coverage & completeness: every country with active courses (AU 26,103, NZ 6,475, CA 2,382 on 2 Oct), with the
--    country on each row; provider tiers are ranked within each country; reads filter by country and provider; a provider
--    search for the filter. Daily history before 2 Oct was Australia only and is labelled AU (new table
--    pipeline.course_coverage_daily_by_country; the old daily table is unchanged).
-- Every function edit is behind an md5 guard. No rows deleted.

-- 1. retire course-page pattern requests
update pipeline.refresh_requests
   set status = 'cancelled', schedule_error = 'retired (Decision 213): course pages are found by the course-link search'
 where revalidation_ref like 'A23-SOURCE-PATTERN:%' and status in ('queued','blocked','failed');

do $h$
declare s text; d text; v text;
  o1 text := $o$'manual_governed',case when v_l3_ready then 'queued' else 'blocked' end,$o$;
  n1 text := $n$'manual_governed','cancelled',$n$;
  o2 text := $o$case when v_l3_ready then null else 'source_pattern_profile_not_executable' end$o$;
  n2 text := $n$'retired (Decision 213): course pages are found by the course-link search'$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'layer2_scale_cross_layer_handoff';
  v := md5(s);
  if v is distinct from 'f4ce745bd0f8a28537cf42d90a4f06cc' then raise exception 'layer2_scale_cross_layer_handoff changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'request status not found once'; end if;
  if (length(d) - length(replace(d, o2, ''))) / length(o2) <> 1 then raise exception 'request error not found once'; end if;
  execute replace(replace(d, o1, n1), o2, n2);
end $h$;

-- 2. fee schedules: waiting first, up to 300
do $f$
declare s text; d text; v text;
  o text := $o$where f.status = 'parsed' order by f.read_at desc limit greatest(1, least(coalesce(p_limit, 50), 200))$o$;
  n text := $n$where f.status = 'parsed' order by (f.decision is null) desc, f.read_at desc limit greatest(1, least(coalesce(p_limit, 50), 300))$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'admin_provider_fee_schedules_read';
  v := md5(s);
  if v is distinct from 'd1f1c69a15d659a8cb3f50488219343d' then raise exception 'admin_provider_fee_schedules_read changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'document order not found once'; end if;
  execute replace(d, o, n);
end $f$;

-- 3. coverage by country
alter table pipeline.course_attribute_coverage add column if not exists country_code text;
alter table pipeline.course_completeness add column if not exists country_code text;
alter table pipeline.completeness_daily add column if not exists country_code text;
-- daily attribute counts by country (the old table, Australia only, stays as it is)
create table if not exists pipeline.course_coverage_daily_by_country (
  snapshot_date date not null, country_code text not null, attribute text not null, state text not null, tier text not null,
  courses integer not null, computed_at timestamptz not null default now(),
  primary key (snapshot_date, country_code, attribute, state, tier));
alter table pipeline.course_coverage_daily_by_country enable row level security;
revoke all on pipeline.course_coverage_daily_by_country from anon, authenticated;
insert into pipeline.course_coverage_daily_by_country(snapshot_date, country_code, attribute, state, tier, courses, computed_at)
select snapshot_date, 'AU', attribute, state, tier, courses, computed_at from pipeline.course_coverage_daily
on conflict do nothing;
create index if not exists course_attribute_coverage_country_idx on pipeline.course_attribute_coverage (country_code, attribute, state);
create index if not exists course_attribute_coverage_provider_idx on pipeline.course_attribute_coverage (provider_id, attribute);
-- history before this change counted Australian courses only
update pipeline.completeness_daily set country_code = 'AU' where scope = 'provider' and country_code is null;
insert into pipeline.completeness_daily(snapshot_date, scope, scope_id, courses, completeness, accounted_pct, fully_complete, computed_at, country_code)
select snapshot_date, 'country:AU', null, courses, completeness, accounted_pct, fully_complete, computed_at, 'AU'
  from pipeline.completeness_daily d where d.scope = 'platform'
   and not exists (select 1 from pipeline.completeness_daily x where x.scope = 'country:AU' and x.snapshot_date = d.snapshot_date);

do $g$
declare v text;
begin
  select md5(p.prosrc) into v from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'security' and p.proname = 'admin_course_coverage_read';
  if v is distinct from 'e4ed662e9f99d15cf65138c8624e73b2' then raise exception 'admin_course_coverage_read changed (md5 %); not replacing', v; end if;
end $g$;

-- the hourly builds: every country, country on each row (patched in place)
do $b$
declare s text; d text; v text; o text[]; n text[]; i int;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'course_coverage_build_v1';
  o := array[
    E'select co.id course_id, co.provider_id, co.duration_value\n      from catalogue.courses co join catalogue.providers p on p.id=co.provider_id join ref.countries k on k.id=p.country_id\n     where co.lifecycle_status=''active'' and k.iso_alpha2=''AU'';',
    'from (select provider_id, row_number() over (order by count(*) desc, provider_id) rk from _c group by provider_id) x;',
    'insert into pipeline.course_attribute_coverage(course_id,provider_id,attribute,state,tier,computed_at)',
    E'    t.tier, now()\n  from _c c join _val v',
    'select current_date, attribute, state, tier, count(*) from pipeline.course_attribute_coverage group by 2,3,4;'];
  n := array[
    E'select co.id course_id, co.provider_id, co.duration_value, k.iso_alpha2::text country_code\n      from catalogue.courses co join catalogue.providers p on p.id=co.provider_id join ref.countries k on k.id=p.country_id\n     where co.lifecycle_status=''active''; -- Decision 213: every country',
    'from (select provider_id, row_number() over (partition by min(country_code) order by count(*) desc, provider_id) rk from _c group by provider_id) x; -- tiers within each country',
    'insert into pipeline.course_attribute_coverage(course_id,provider_id,attribute,state,tier,computed_at,country_code)',
    E'    t.tier, now(), c.country_code\n  from _c c join _val v',
    E'select current_date, attribute, state, tier, count(*) from pipeline.course_attribute_coverage where country_code=''AU'' group by 2,3,4;\n'
    || E'  -- Decision 213: daily counts by country\n'
    || E'  update pipeline.course_coverage_daily_by_country set courses = 0, computed_at = now() where snapshot_date = current_date;\n'
    || E'  insert into pipeline.course_coverage_daily_by_country(snapshot_date,country_code,attribute,state,tier,courses)\n'
    || E'  select current_date, country_code, attribute, state, tier, count(*) from pipeline.course_attribute_coverage group by 2,3,4,5\n'
    || E'  on conflict (snapshot_date,country_code,attribute,state,tier) do update set courses = excluded.courses, computed_at = now();'];
  v := md5(s);
  if v is distinct from '00b8068b7aad60f332eb5d0057dfae9a' then raise exception 'course_coverage_build_v1 changed (md5 %); not replacing', v; end if;
  for i in 1..array_length(o,1) loop
    if (length(d) - length(replace(d, o[i], ''))) / length(o[i]) <> 1 then raise exception 'coverage build piece % not found once', i; end if;
    d := replace(d, o[i], n[i]);
  end loop;
  execute d;

  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'course_completeness_build_v1';
  o := array[
    'insert into pipeline.course_completeness(course_id,provider_id,tier,attributes,admitted,accounted,completeness,accounted_pct,missing)',
    E'coalesce(array_agg(attribute order by attribute) filter (where state<>''admitted''),''{}'')\n    from pipeline.course_attribute_coverage group by course_id;',
    E'  select to_jsonb(d) - ''scope_id'' into v from'];
  n := array[
    'insert into pipeline.course_completeness(course_id,provider_id,tier,attributes,admitted,accounted,completeness,accounted_pct,missing,country_code)',
    E'coalesce(array_agg(attribute order by attribute) filter (where state<>''admitted''),''{}''),\n         max(country_code)\n    from pipeline.course_attribute_coverage group by course_id;',
    E'  -- Decision 213: one row per country; provider rows carry their country\n'
    || E'  insert into pipeline.completeness_daily(snapshot_date,scope,scope_id,courses,completeness,accounted_pct,fully_complete,country_code)\n'
    || E'  select current_date,''country:''||country_code,null,count(*),round(avg(completeness),1),round(avg(accounted_pct),1),count(*) filter (where admitted=attributes),country_code\n'
    || E'    from pipeline.course_completeness group by country_code;\n'
    || E'  update pipeline.completeness_daily x set country_code = (select max(c.country_code) from pipeline.course_completeness c where c.provider_id = x.scope_id)\n'
    || E'   where x.snapshot_date = current_date and x.scope = ''provider'';\n'
    || E'  select to_jsonb(d) - ''scope_id'' into v from'];
  v := md5(s);
  if v is distinct from 'd3be4b3fd26dd3c70a2e56daceeed3c9' then raise exception 'course_completeness_build_v1 changed (md5 %); not replacing', v; end if;
  for i in 1..array_length(o,1) loop
    if (length(d) - length(replace(d, o[i], ''))) / length(o[i]) <> 1 then raise exception 'completeness build piece % not found once', i; end if;
    d := replace(d, o[i], n[i]);
  end loop;
  execute d;
end $b$;

create or replace function security.admin_course_coverage_read(p_operation text, p_args jsonb)
 returns jsonb language plpgsql stable security definer
 set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'security', 'auth'
as $function$
declare v_tier text:=nullif(p_args->>'tier',''); v jsonb;
  v_cstate text:=nullif(p_args->>'completeness_state','');
  -- Decision 213: country (ISO code) and provider filters
  v_country text:=upper(nullif(btrim(coalesce(p_args->>'country','')),''));
  v_provider uuid:=nullif(p_args->>'provider','')::uuid;
  c_states constant text[]:=array['present','source_null','not_applicable','zero','suppressed','not_yet_enriched','stale','ambiguous','rejected'];
  c_attrs constant text[]:=array['official_url','provider_tuition','english','intakes','registered_tuition','duration','campus'];
begin
  if auth.uid() is null or security.current_role_rank()<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  if p_operation='course_coverage_providers' then
    return coalesce((select jsonb_agg(jsonb_build_object('id',q.provider_id,'name',q.name,'country',q.country_code,'courses',q.n) order by q.n desc, q.name)
      from (select x.provider_id, max(coalesce(p.display_name,p.canonical_name)) name, max(x.country_code) country_code, count(*) n
              from pipeline.course_completeness x join catalogue.providers p on p.id=x.provider_id
             where (v_country is null or x.country_code=v_country)
               and (coalesce(p_args->>'query','')='' or coalesce(p.display_name,p.canonical_name) ilike '%'||(p_args->>'query')||'%' or p.canonical_name ilike '%'||(p_args->>'query')||'%')
             group by x.provider_id order by count(*) desc limit 30) q),'[]'::jsonb);
  elsif p_operation='course_coverage' then
    with a as (select * from pipeline.course_attribute_coverage x
                where (v_tier is null or x.tier=v_tier) and (v_country is null or x.country_code=v_country) and (v_provider is null or x.provider_id=v_provider)),
         cc as (select * from pipeline.course_completeness x
                where (v_tier is null or x.tier=v_tier) and (v_country is null or x.country_code=v_country) and (v_provider is null or x.provider_id=v_provider))
    select jsonb_build_object(
      'computed_at',(select max(computed_at) from pipeline.course_attribute_coverage),
      'courses',(select count(distinct course_id) from a),
      'providers',(select count(distinct provider_id) from a),
      'tier',v_tier,'country',v_country,
      'provider',case when v_provider is null then null else (select jsonb_build_object('id',p.id,'name',coalesce(p.display_name,p.canonical_name)) from catalogue.providers p where p.id=v_provider) end,
      'countries',(select jsonb_agg(jsonb_build_object('code',country_code,'courses',n,'providers',pn) order by n desc) from (
          select country_code, count(*) n, count(distinct provider_id) pn from pipeline.course_completeness group by 1) k),
      'attributes',(select jsonb_agg(jsonb_build_object('attribute',attribute,'states',states,'total',total) order by ord) from (
          select attribute, jsonb_object_agg(state,n) states, sum(n) total, min(array_position(c_attrs,attribute)) ord
            from (select attribute,state,count(*) n from a group by 1,2) s group by attribute) x),
      'tiers',(select jsonb_agg(jsonb_build_object('tier',tier,'courses',n,'providers',p) order by tier) from (
          select tier, count(distinct course_id) n, count(distinct provider_id) p from pipeline.course_attribute_coverage
           where (v_country is null or country_code=v_country) group by tier) t),
      -- daily history has no provider dimension: no attribute trend for one provider
      'trend',case when v_provider is null then (select jsonb_agg(jsonb_build_object('date',snapshot_date,'attribute',attribute,'admitted',adm,'total',tot) order by snapshot_date, attribute) from (
          select snapshot_date, attribute, sum(courses) filter (where state='admitted') adm, sum(courses) tot
            from pipeline.course_coverage_daily_by_country where snapshot_date>=current_date-60 and (v_tier is null or tier=v_tier) and (v_country is null or country_code=v_country) group by 1,2) d) end,
      'completeness_states',(select jsonb_agg(jsonb_build_object('attribute',attribute,'states',
            (select jsonb_object_agg(k, coalesce((cs->>k)::int,0)) from unnest(c_states) k),'total',total) order by ord) from (
          select attribute, jsonb_object_agg(cstate,n) cs, sum(n) total, min(array_position(c_attrs,attribute)) ord
            from (select attribute, security.coverage_completeness_state(state) cstate, sum(n) n from (
                    select attribute,state,count(*) n from a group by 1,2) s0
                  group by 1,2) s group by attribute) x),
      'completeness_state_map',(select jsonb_object_agg(s, security.coverage_completeness_state(s))
          from unnest(array['admitted','candidate','in_review','awaiting_l3','not_on_page','blocked','page_found','site_known','no_website','missing_l1']) s),
      'completeness',(select jsonb_build_object(
            'computed_at',max(cc.computed_at),
            'courses',count(*),
            'attributes',max(cc.attributes),
            'completeness',round(avg(cc.completeness),1),
            'accounted_pct',round(avg(cc.accounted_pct),1),
            'fully_complete',count(*) filter (where cc.admitted=cc.attributes),
            'by_admitted',(select jsonb_agg(jsonb_build_object('admitted',b.admitted,'courses',b.n) order by b.admitted) from (
                select c2.admitted, count(*) n from cc c2 group by 1) b),
            'trend',case when v_tier is null then (select jsonb_agg(jsonb_build_object('date',d.snapshot_date,'courses',d.courses,'completeness',d.completeness,
                        'accounted_pct',d.accounted_pct,'fully_complete',d.fully_complete,'computed_at',d.computed_at) order by d.snapshot_date)
                      from pipeline.completeness_daily d where d.snapshot_date>=current_date-60
                       and case when v_provider is not null then d.scope='provider' and d.scope_id=v_provider
                                when v_country is not null then d.scope='country:'||v_country
                                else d.scope='platform' end) end)
          from cc)
    ) into v;
    return v;
  elsif p_operation='course_coverage_courses' then
    if v_cstate is not null and not (v_cstate = any(c_states)) then raise exception 'unknown completeness state %', v_cstate; end if;
    select jsonb_build_object('total',(select count(*) from pipeline.course_attribute_coverage x where x.attribute=p_args->>'attribute'
                 and (case when v_cstate is not null then security.coverage_completeness_state(x.state)=v_cstate else x.state=p_args->>'state' end)
                 and (v_tier is null or x.tier=v_tier) and (v_country is null or x.country_code=v_country) and (v_provider is null or x.provider_id=v_provider)),
      'items',coalesce((select jsonb_agg(r) from (
        select x.course_id, c.canonical_title title, coalesce(p.display_name,p.canonical_name) provider_name, x.tier, x.country_code,
               (select min(registration_code) from catalogue.course_registrations cr where cr.course_id=x.course_id and lower(cr.scheme)='cricos') cricos,
               x.state, security.coverage_completeness_state(x.state) completeness_state, cc.completeness, cc.accounted_pct
          from pipeline.course_attribute_coverage x join catalogue.courses c on c.id=x.course_id join catalogue.providers p on p.id=x.provider_id
          left join pipeline.course_completeness cc on cc.course_id=x.course_id
         where x.attribute=p_args->>'attribute'
           and (case when v_cstate is not null then security.coverage_completeness_state(x.state)=v_cstate else x.state=p_args->>'state' end)
           and (v_tier is null or x.tier=v_tier) and (v_country is null or x.country_code=v_country) and (v_provider is null or x.provider_id=v_provider)
         order by coalesce(p.display_name,p.canonical_name), c.canonical_title
         limit least(coalesce(nullif(p_args->>'limit','')::int,50),200) offset greatest(coalesce(nullif(p_args->>'offset','')::int,0),0)) r),'[]'::jsonb))
      into v;
    return v;
  end if;
  raise exception 'unknown coverage operation %', p_operation;
end $function$;

-- the provider search goes through public.admin_read (runs as the signed-in user)
do $r$
declare s text; d text; v text;
  o text := $o$if p_operation in ('course_coverage','course_coverage_courses') then$o$;
  n text := $n$if p_operation in ('course_coverage','course_coverage_courses','course_coverage_providers') then$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'admin_read';
  v := md5(s);
  if v is distinct from '9b52ca165865fc62d56a2d18c681dd5c' then raise exception 'admin_read changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'coverage route not found once'; end if;
  execute replace(d, o, n);
end $r$;

-- rebuild now so the screen shows every country
select security.course_coverage_build_v1();
select security.course_completeness_build_v1();
