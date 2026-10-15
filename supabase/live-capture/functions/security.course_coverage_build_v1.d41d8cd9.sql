CREATE OR REPLACE FUNCTION security.course_coverage_build_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'ref', 'security'
AS $function$
declare v_n int; v_t0 timestamptz:=clock_timestamp();
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  create temp table _c on commit drop as
    select co.id course_id, co.provider_id, co.duration_value, k.iso_alpha2::text country_code
      from catalogue.courses co join catalogue.providers p on p.id=co.provider_id join ref.countries k on k.id=p.country_id
     where co.lifecycle_status='active'; -- Decision 213: every country
  create temp table _tier on commit drop as
    select provider_id, case when rk<=10 then 'top_10' when rk<=40 then 'top_11_40' when rk<=100 then 'top_41_100' else 'rest' end tier
      from (select provider_id, row_number() over (partition by min(country_code) order by count(*) desc, provider_id) rk from _c group by provider_id) x; -- tiers within each country
  create temp table _site on commit drop as
    select t.provider_id from _tier t join catalogue.providers p on p.id=t.provider_id
     where nullif(btrim(p.website),'') is not null or exists(select 1 from pipeline.provider_discovery_links l where l.provider_id=t.provider_id);
  create temp table _found on commit drop as
    select distinct course_id from pipeline.layer2_course_discovery_candidates where selected and course_id is not null;
  create temp table _read on commit drop as
    select entity_id course_id, bool_or(status in ('resolved_l2','layer3_required')) read_ok, bool_or(status='blocked') blocked
      from pipeline.layer2_run_items where entity_type='course' group by entity_id;
  create temp table _sw on commit drop as
    select course_id, status, read_status, identity_basis,
           (read_status='read' and identity_basis='cricos_code') verified,
           coalesce((candidates->'fee'->>'value') is not null,false) c_tuition,
           coalesce(candidates->'english' ? 'ielts_overall' or candidates->'english' ? 'pte_overall' or candidates->'english' ? 'toefl_overall',false) c_english,
           coalesce(jsonb_array_length(candidates->'intakes')>0,false) c_intakes
      from pipeline.coverage_course_pages;
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
  insert into pipeline.course_attribute_coverage(course_id,provider_id,attribute,state,tier,computed_at,country_code)
  select c.course_id, c.provider_id, a.attribute,
    case
      when a.l1 then case when a.has then 'admitted' else 'missing_l1' end
      when a.has then 'admitted'
      when exists(select 1 from _l4 x where x.course_id=c.course_id and x.attribute=a.attribute) then 'in_review'
      when exists(select 1 from _l3 x where x.course_id=c.course_id and x.attribute=a.attribute) then 'awaiting_l3'
      when sw.verified and (a.attribute='official_url' or (a.attribute='provider_tuition' and sw.c_tuition) or (a.attribute='english' and sw.c_english) or (a.attribute='intakes' and sw.c_intakes)) then 'candidate'
      when r.read_ok or sw.verified then 'not_on_page'
      when r.blocked or sw.read_status in ('blocked','robots_disallowed') then 'blocked'
      when f.course_id is not null or v.url or sw.status='bound' then 'page_found'
      when s.provider_id is not null then 'site_known'
      else 'no_website' end,
    t.tier, now(), c.country_code
  from _c c join _val v using (course_id) join _tier t using (provider_id)
  left join _read r using (course_id) left join _found f using (course_id) left join _sw sw using (course_id) left join _site s on s.provider_id=c.provider_id
  cross join lateral (values
    ('official_url', v.url, false), ('provider_tuition', v.tuition, false), ('english', v.english, false), ('intakes', v.intakes, false),
    ('registered_tuition', v.reg_tuition, true), ('duration', c.duration_value is not null, true), ('campus', v.campus, true)) a(attribute, has, l1);
  get diagnostics v_n=row_count;

  delete from pipeline.course_coverage_daily where snapshot_date=current_date;
  insert into pipeline.course_coverage_daily(snapshot_date,attribute,state,tier,courses)
  select current_date, attribute, state, tier, count(*) from pipeline.course_attribute_coverage where country_code='AU' group by 2,3,4;
  -- Decision 213: daily counts by country
  update pipeline.course_coverage_daily_by_country set courses = 0, computed_at = now() where snapshot_date = current_date;
  insert into pipeline.course_coverage_daily_by_country(snapshot_date,country_code,attribute,state,tier,courses)
  select current_date, country_code, attribute, state, tier, count(*) from pipeline.course_attribute_coverage group by 2,3,4,5
  on conflict (snapshot_date,country_code,attribute,state,tier) do update set courses = excluded.courses, computed_at = now();
  return jsonb_build_object('rows',v_n,'courses',(select count(*) from _c),'ms',round(extract(epoch from clock_timestamp()-v_t0)*1000));
end $function$
