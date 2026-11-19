-- CF-247 R12 (with A6): the Course coverage view reports completeness states and the course completeness score.
-- Additive read only. No table, cron job, consumer API, scholarship or coverage-admission function is changed.
--
-- 1. New helper security.coverage_completeness_state(text): maps the hourly pipeline state of one course attribute
--    (pipeline.course_attribute_coverage.state) to the platform's nine completeness states (Design Reference §3):
--      present           <- admitted
--      source_null       <- not_on_page (the official page was read and does not publish it),
--                           missing_l1 (the register holds no value)
--      ambiguous         <- candidate, awaiting_l3, in_review (a value was found and awaits a decision)
--      not_yet_enriched  <- page_found, blocked, site_known, no_website (the source has not been read yet)
--    not_applicable, zero, suppressed, stale and rejected are not produced by the hourly build yet; the read
--    returns them as 0 so every view shows all nine states.
-- 2. security.admin_course_coverage_read(text,jsonb), checksum-guarded against the live definition reviewed on
--    29 Sep 2026 (md5(prosrc) a624cf66621a749cdd395cf530466927), is replaced with the same body plus:
--      course_coverage          + completeness_states (nine states per attribute), completeness_state_map,
--                                 completeness (score, accounted for, fully complete, by admitted-attribute count,
--                                 60-day platform trend from pipeline.completeness_daily)
--      course_coverage_courses  + optional completeness_state filter (instead of state); each item gains
--                                 completeness and accounted_pct from pipeline.course_completeness
--    Existing keys and the existing state filter are unchanged.

create or replace function security.coverage_completeness_state(p_state text)
returns text language sql immutable parallel safe set search_path to 'pg_catalog' as $f$
  select case p_state
    when 'admitted' then 'present'
    when 'not_on_page' then 'source_null'
    when 'missing_l1' then 'source_null'
    when 'candidate' then 'ambiguous'
    when 'awaiting_l3' then 'ambiguous'
    when 'in_review' then 'ambiguous'
    else 'not_yet_enriched' end
$f$;
revoke all on function security.coverage_completeness_state(text) from public;
do $g$ begin
  if exists(select 1 from pg_roles where rolname='anon') then execute 'revoke all on function security.coverage_completeness_state(text) from anon'; end if;
  if exists(select 1 from pg_roles where rolname='authenticated') then execute 'revoke all on function security.coverage_completeness_state(text) from authenticated'; end if;
end $g$;

do $guard$
begin
  if (select md5(prosrc) from pg_proc where oid='security.admin_course_coverage_read(text,jsonb)'::regprocedure)<>'a624cf66621a749cdd395cf530466927' then
    raise exception 'security.admin_course_coverage_read changed since review; not replaced'; end if;
end $guard$;

create or replace function security.admin_course_coverage_read(p_operation text, p_args jsonb)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'security', 'auth'
as $function$
declare v_tier text:=nullif(p_args->>'tier',''); v jsonb;
  v_cstate text:=nullif(p_args->>'completeness_state','');
  c_states constant text[]:=array['present','source_null','not_applicable','zero','suppressed','not_yet_enriched','stale','ambiguous','rejected'];
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
            from pipeline.course_coverage_daily where snapshot_date>=current_date-60 and (v_tier is null or tier=v_tier) group by 1,2) d),
      -- R12: the nine completeness states per attribute (all nine keys present, zero when not produced)
      'completeness_states',(select jsonb_agg(jsonb_build_object('attribute',attribute,'states',
            (select jsonb_object_agg(k, coalesce((cs->>k)::int,0)) from unnest(c_states) k),'total',total) order by ord) from (
          select attribute, jsonb_object_agg(cstate,n) cs, sum(n) total,
                 min(array_position(array['official_url','provider_tuition','english','intakes','registered_tuition','duration','campus'],attribute)) ord
            from (select attribute, security.coverage_completeness_state(state) cstate, sum(n) n from (
                    select attribute,state,count(*) n from pipeline.course_attribute_coverage where v_tier is null or tier=v_tier group by 1,2) s0
                  group by 1,2) s group by attribute) a),
      'completeness_state_map',(select jsonb_object_agg(s, security.coverage_completeness_state(s))
          from unnest(array['admitted','candidate','in_review','awaiting_l3','not_on_page','blocked','page_found','site_known','no_website','missing_l1']) s),
      -- A6: course completeness score (share of a course's attributes admitted), accounted for, fully complete
      'completeness',(select jsonb_build_object(
            'computed_at',max(cc.computed_at),
            'courses',count(*),
            'attributes',max(cc.attributes),
            'completeness',round(avg(cc.completeness),1),
            'accounted_pct',round(avg(cc.accounted_pct),1),
            'fully_complete',count(*) filter (where cc.admitted=cc.attributes),
            'by_admitted',(select jsonb_agg(jsonb_build_object('admitted',b.admitted,'courses',b.n) order by b.admitted) from (
                select c2.admitted, count(*) n from pipeline.course_completeness c2 where v_tier is null or c2.tier=v_tier group by 1) b),
            'trend',case when v_tier is null then (select jsonb_agg(jsonb_build_object('date',d.snapshot_date,'courses',d.courses,'completeness',d.completeness,
                        'accounted_pct',d.accounted_pct,'fully_complete',d.fully_complete,'computed_at',d.computed_at) order by d.snapshot_date)
                      from pipeline.completeness_daily d where d.scope='platform' and d.snapshot_date>=current_date-60) end)
          from pipeline.course_completeness cc where v_tier is null or cc.tier=v_tier)
    ) into v;
    return v;
  elsif p_operation='course_coverage_courses' then
    if v_cstate is not null and not (v_cstate = any(c_states)) then raise exception 'unknown completeness state %', v_cstate; end if;
    select jsonb_build_object('total',(select count(*) from pipeline.course_attribute_coverage x where x.attribute=p_args->>'attribute'
                 and (case when v_cstate is not null then security.coverage_completeness_state(x.state)=v_cstate else x.state=p_args->>'state' end)
                 and (v_tier is null or x.tier=v_tier)),
      'items',coalesce((select jsonb_agg(r) from (
        select x.course_id, c.canonical_title title, coalesce(p.display_name,p.canonical_name) provider_name, x.tier,
               (select min(registration_code) from catalogue.course_registrations cr where cr.course_id=x.course_id and lower(cr.scheme)='cricos') cricos,
               x.state, security.coverage_completeness_state(x.state) completeness_state, cc.completeness, cc.accounted_pct
          from pipeline.course_attribute_coverage x join catalogue.courses c on c.id=x.course_id join catalogue.providers p on p.id=x.provider_id
          left join pipeline.course_completeness cc on cc.course_id=x.course_id
         where x.attribute=p_args->>'attribute'
           and (case when v_cstate is not null then security.coverage_completeness_state(x.state)=v_cstate else x.state=p_args->>'state' end)
           and (v_tier is null or x.tier=v_tier)
         order by coalesce(p.display_name,p.canonical_name), c.canonical_title
         limit least(coalesce(nullif(p_args->>'limit','')::int,50),200) offset greatest(coalesce(nullif(p_args->>'offset','')::int,0),0)) r),'[]'::jsonb))
      into v;
    return v;
  end if;
  raise exception 'unknown coverage operation %', p_operation;
end $function$;
revoke all on function security.admin_course_coverage_read(text,jsonb) from public, anon;
grant execute on function security.admin_course_coverage_read(text,jsonb) to authenticated;
