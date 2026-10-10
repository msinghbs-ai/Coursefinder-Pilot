-- CF-247 complete-coverage programme (Platform Admin direction 29 Sep 2026): every active Australian course is
-- accounted for, attribute by attribute, and the statistics are kept daily.
--
-- One state per course and attribute, in this order of precedence:
--   admitted        a governed value is in the catalogue
--   in_review       a Layer 4 item is open for it (a person decides)
--   awaiting_l3     a Layer 3 check is queued
--   not_on_page     the course page was read and the value is not published there
--   blocked         the provider site refused the read
--   page_found      the course page is known but not read yet
--   site_known      the provider site is known; the course page is not found yet
--   no_website      no provider website is known
-- Registry attributes from CRICOS (registered tuition, duration, campus) are shown alongside as Layer 1.
-- pipeline.course_attribute_coverage holds the current state per course; pipeline.course_coverage_daily keeps one
-- row per day, attribute, state and provider tier (tier by provider size: top 10, 11-40, 41-100, the rest).

create table if not exists pipeline.course_attribute_coverage(
  course_id uuid not null, provider_id uuid not null, attribute text not null, state text not null,
  tier text not null, computed_at timestamptz not null default now(), primary key(course_id, attribute));
create index if not exists course_attribute_coverage_attr_state on pipeline.course_attribute_coverage(attribute, state, tier);
create table if not exists pipeline.course_coverage_daily(
  snapshot_date date not null, attribute text not null, state text not null, tier text not null, courses integer not null,
  computed_at timestamptz not null default now(), primary key(snapshot_date, attribute, state, tier));
alter table pipeline.course_attribute_coverage enable row level security;
alter table pipeline.course_coverage_daily enable row level security;
revoke all on pipeline.course_attribute_coverage, pipeline.course_coverage_daily from public, anon, authenticated;

create or replace function security.course_coverage_build_v1()
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','catalogue','pipeline','ref','security' as $f$
declare v_n int; v_t0 timestamptz:=clock_timestamp();
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  create temp table _c on commit drop as
    select co.id course_id, co.provider_id, co.duration_value
      from catalogue.courses co join catalogue.providers p on p.id=co.provider_id join ref.countries k on k.id=p.country_id
     where co.lifecycle_status='active' and k.iso_alpha2='AU';
  create temp table _tier on commit drop as
    select provider_id, case when rk<=10 then 'top_10' when rk<=40 then 'top_11_40' when rk<=100 then 'top_41_100' else 'rest' end tier
      from (select provider_id, row_number() over (order by count(*) desc, provider_id) rk from _c group by provider_id) x;
  create temp table _site on commit drop as
    select t.provider_id from _tier t join catalogue.providers p on p.id=t.provider_id
     where nullif(btrim(p.website),'') is not null or exists(select 1 from pipeline.provider_discovery_links l where l.provider_id=t.provider_id);
  create temp table _found on commit drop as
    select distinct course_id from pipeline.layer2_course_discovery_candidates where selected and course_id is not null;
  create temp table _read on commit drop as
    select entity_id course_id, bool_or(status in ('resolved_l2','layer3_required')) read_ok, bool_or(status='blocked') blocked
      from pipeline.layer2_run_items where entity_type='course' group by entity_id;
  create temp table _val on commit drop as
    select c.course_id,
      exists(select 1 from catalogue.course_links l where l.course_id=c.course_id and l.status='active' and l.link_type='official_course') url,
      exists(select 1 from catalogue.course_fees f where f.course_id=c.course_id and f.status='active' and f.fee_type='provider_current_tuition') tuition,
      exists(select 1 from catalogue.course_english_requirements e where e.course_id=c.course_id and e.status='active') english,
      exists(select 1 from catalogue.course_intakes i where i.course_id=c.course_id and coalesce(i.status,'active')='active') intakes,
      exists(select 1 from catalogue.course_fees f where f.course_id=c.course_id and f.status='active' and f.fee_type='tuition') reg_tuition,
      exists(select 1 from catalogue.course_campuses cc where cc.course_id=c.course_id) campus
    from _c c;
  create temp table _l4 on commit drop as
    select entity_id course_id, case when field_code in ('official_course_url') then 'official_url'
                                     when field_code in ('provider_current_tuition_validation','provider_current_tuition') then 'provider_tuition'
                                     when field_code ilike '%english%' then 'english' when field_code ilike '%intake%' then 'intakes' end attribute
      from pipeline.layer4_review_items where entity_type='course' and status='pending'
    union
    select entity_id, case when task_class='provider_current_tuition_validation' then 'provider_tuition' when task_class ilike '%english%' then 'english'
                           when task_class ilike '%intake%' then 'intakes' when task_class ilike '%url%' then 'official_url' end
      from pipeline.layer3_work_items where entity_type='course' and status='layer4_required';
  create temp table _l3 on commit drop as
    select entity_id course_id, case when task_class='provider_current_tuition_validation' then 'provider_tuition' when task_class ilike '%english%' then 'english'
                                     when task_class ilike '%intake%' then 'intakes' when task_class ilike '%url%' then 'official_url' end attribute
      from pipeline.layer3_work_items where entity_type='course' and status in ('pending','reserved','failed','retry');

  truncate pipeline.course_attribute_coverage;
  insert into pipeline.course_attribute_coverage(course_id,provider_id,attribute,state,tier,computed_at)
  select c.course_id, c.provider_id, a.attribute,
    case
      when a.l1 then case when a.has then 'admitted' else 'missing_l1' end
      when a.has then 'admitted'
      when exists(select 1 from _l4 x where x.course_id=c.course_id and x.attribute=a.attribute) then 'in_review'
      when exists(select 1 from _l3 x where x.course_id=c.course_id and x.attribute=a.attribute) then 'awaiting_l3'
      when r.read_ok then 'not_on_page'
      when r.blocked then 'blocked'
      when f.course_id is not null or v.url then 'page_found'
      when s.provider_id is not null then 'site_known'
      else 'no_website' end,
    t.tier, now()
  from _c c join _val v using (course_id) join _tier t using (provider_id)
  left join _read r using (course_id) left join _found f using (course_id) left join _site s on s.provider_id=c.provider_id
  cross join lateral (values
    ('official_url', v.url, false), ('provider_tuition', v.tuition, false), ('english', v.english, false), ('intakes', v.intakes, false),
    ('registered_tuition', v.reg_tuition, true), ('duration', c.duration_value is not null, true), ('campus', v.campus, true)) a(attribute, has, l1);
  get diagnostics v_n=row_count;

  delete from pipeline.course_coverage_daily where snapshot_date=current_date;
  insert into pipeline.course_coverage_daily(snapshot_date,attribute,state,tier,courses)
  select current_date, attribute, state, tier, count(*) from pipeline.course_attribute_coverage group by 2,3,4;
  return jsonb_build_object('rows',v_n,'courses',(select count(*) from _c),'ms',round(extract(epoch from clock_timestamp()-v_t0)*1000));
end $f$;
revoke all on function security.course_coverage_build_v1() from public, anon, authenticated;

-- Admin read: summary by attribute and state (optionally one tier), daily trend, and a paged course list for one
-- attribute/state. Any assigned CourseFinder role may read.
create or replace function security.admin_course_coverage_read(p_operation text, p_args jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','catalogue','pipeline','security','auth' as $f$
declare v_tier text:=nullif(p_args->>'tier',''); v jsonb;
begin
  if auth.uid() is null or security.current_role_rank()<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  if p_operation='course_coverage' then
    select jsonb_build_object(
      'computed_at',(select max(computed_at) from pipeline.course_attribute_coverage),
      'courses',(select count(distinct course_id) from pipeline.course_attribute_coverage where v_tier is null or tier=v_tier),
      'providers',(select count(distinct provider_id) from pipeline.course_attribute_coverage where v_tier is null or tier=v_tier),
      'tier',v_tier,
      'attributes',(select jsonb_agg(jsonb_build_object('attribute',attribute,'states',states,'total',total) order by ord) from (
          select attribute, jsonb_object_agg(state,n) states, sum(n) total,
                 min(array_position(array['official_url','provider_tuition','english','intakes','registered_tuition','duration','campus'],attribute)) ord
            from (select attribute,state,count(*) n from pipeline.course_attribute_coverage where v_tier is null or tier=v_tier group by 1,2) s group by attribute) a),
      'tiers',(select jsonb_agg(jsonb_build_object('tier',tier,'courses',n,'providers',p) order by tier) from (
          select tier, count(distinct course_id) n, count(distinct provider_id) p from pipeline.course_attribute_coverage group by tier) t),
      'trend',(select jsonb_agg(jsonb_build_object('date',snapshot_date,'attribute',attribute,'admitted',adm,'total',tot) order by snapshot_date, attribute) from (
          select snapshot_date, attribute, sum(courses) filter (where state='admitted') adm, sum(courses) tot
            from pipeline.course_coverage_daily where snapshot_date>=current_date-60 and (v_tier is null or tier=v_tier) group by 1,2) d)
    ) into v;
    return v;
  elsif p_operation='course_coverage_courses' then
    select jsonb_build_object('total',(select count(*) from pipeline.course_attribute_coverage x where x.attribute=p_args->>'attribute' and x.state=p_args->>'state' and (v_tier is null or x.tier=v_tier)),
      'items',coalesce((select jsonb_agg(r) from (
        select x.course_id, c.canonical_title title, p.name provider_name, x.tier,
               (select min(registration_code) from catalogue.course_registrations cr where cr.course_id=x.course_id and lower(cr.scheme)='cricos') cricos
          from pipeline.course_attribute_coverage x join catalogue.courses c on c.id=x.course_id join catalogue.providers p on p.id=x.provider_id
         where x.attribute=p_args->>'attribute' and x.state=p_args->>'state' and (v_tier is null or x.tier=v_tier)
         order by p.name, c.canonical_title
         limit least(coalesce(nullif(p_args->>'limit','')::int,50),200) offset greatest(coalesce(nullif(p_args->>'offset','')::int,0),0)) r),'[]'::jsonb))
      into v;
    return v;
  end if;
  raise exception 'unknown coverage operation %', p_operation;
end $f$;
revoke all on function security.admin_course_coverage_read(text,jsonb) from public, anon;
grant execute on function security.admin_course_coverage_read(text,jsonb) to authenticated;

-- admin_read dispatch: additive branch after 'platform_health' (checksum-guarded).
do $patch$
declare v_def text; v_old text; v_new text;
begin
  if (select md5(prosrc) from pg_proc where oid='public.admin_read(text,jsonb)'::regprocedure)<>'40d88bbdf744e7d6e82e1bdaa7aa3b4c' then
    raise exception 'public.admin_read changed since review; not replaced'; end if;
  v_def:=pg_get_functiondef('public.admin_read(text,jsonb)'::regprocedure);
  v_old:=$o$ if p_operation='platform_health' then return security.admin_platform_health_cf221(); end if;$o$;
  v_new:=v_old||E'\n'||$n$ if p_operation in ('course_coverage','course_coverage_courses') then return security.admin_course_coverage_read(p_operation,p_args); end if;$n$;
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1 then raise exception 'dispatch anchor not found exactly once'; end if;
  execute replace(v_def,v_old,v_new);
end $patch$;

-- Rebuilt every hour at :47; the day's row in course_coverage_daily is replaced on each build, so the last build of
-- the day is that day's snapshot.
select cron.schedule('course-coverage-build','47 * * * *',$$select security.course_coverage_build_v1()$$);
select security.course_coverage_build_v1();
