-- CF-247 Decision 162 step 4: the plan still took ~27 s because each intermediate step was inlined and every
-- course re-ran its Table 1 lookups once per CASE branch. Each step is now materialised once; rules unchanged.
do $g$ begin
  if (select md5(prosrc) from pg_proc where oid='security.english_table_plan_v1(text,jsonb,jsonb)'::regprocedure)<>'12267037706bd6c32967e62e23134e4c' then
    raise exception 'security.english_table_plan_v1 changed since review; not replaced'; end if;
end $g$;

create or replace function security.english_table_plan_v1(p_provider_cricos text, p_programs jsonb, p_minimum jsonb)
returns table(course_id uuid, course_cricos text, title text, study_level text, plan text, reason text, program text,
              requirements jsonb, existing jsonb, comparison text)
language plpgsql stable security definer set search_path to 'pg_catalog','catalogue','pipeline','ref','security' as $f$
declare v_provider uuid; v_aliases jsonb;
begin
  select s.provider_id, coalesce(s.metadata->'aliases','{}'::jsonb) into v_provider, v_aliases from pipeline.sources s
   where s.source_type='provider_english_requirements' and s.metadata->>'provider_cricos'=upper(btrim(p_provider_cricos)) limit 1;
  if v_provider is null then raise exception 'no English requirements source for provider %', p_provider_cricos; end if;
  return query
  with t1 as materialized (
    select e->>'name' name, coalesce(e->>'section','coursework') section, e->'requirements' reqs,
           coalesce(v_aliases->>security.english_title_key(e->>'name'), security.english_title_key(e->>'name')) k
      from jsonb_array_elements(coalesce(p_programs,'[]'::jsonb)) e),
  t1t as materialized (select t1.*, security.english_title_tokens(t1.k) tok from t1),
  c as materialized (
    select co.id, co.canonical_title t, security.english_title_key(co.canonical_title) k, sl.code lvl,
           (select min(upper(btrim(cr.registration_code))) from catalogue.course_registrations cr where cr.course_id=co.id and lower(cr.scheme)='cricos') cricos,
           (select coalesce(jsonb_object_agg(et.code, r.overall_score),'{}'::jsonb) from catalogue.course_english_requirements r join ref.english_tests et on et.id=r.english_test_id
             where r.course_id=co.id and r.status='active') ex
      from catalogue.courses co left join ref.study_levels sl on sl.id=co.study_level_id
     where co.provider_id=v_provider and co.lifecycle_status='active'),
  ct as materialized (select c.*, security.english_title_tokens(c.k) tok from c),
  m as materialized (
    select ct.*,
           (select jsonb_agg(jsonb_build_object('name',t1.name,'reqs',t1.reqs)) from t1 where t1.k=ct.k) exact,
           exists(select 1 from t1t where t1t.k<>ct.k and (position(t1t.k in ct.k)>0
                  or (select count(*) from unnest(ct.tok) u where u = any(t1t.tok))::numeric / nullif(greatest(cardinality(ct.tok),cardinality(t1t.tok)),0) >= 0.75)) close
      from ct),
  p as materialized (
    select m.*,
      case when m.exact is not null and (select count(distinct x->'reqs') from jsonb_array_elements(m.exact) x)>1 then 'held'
           when m.exact is not null then 'table1'
           when m.lvl='non_aqf_award' or m.lvl is null then 'held'
           when m.t ~* 'exit award' then 'held'
           when m.lvl in ('doctorate','masters_research') then 'held'
           when m.k ~ '/' or m.k ~ ' and (bachelor|master|doctor|graduate|diploma|associate) (of|in) ' then 'held'
           when m.close then 'held'
           else 'minimum' end pl,
      case when m.exact is not null and (select count(distinct x->'reqs') from jsonb_array_elements(m.exact) x)>1 then 'conflicting Table 1 entries for one name'
           when m.exact is not null then null
           when m.lvl is null then 'study level unknown'
           when m.lvl='non_aqf_award' then 'not an award program'
           when m.t ~* 'exit award' then 'exit award only: not an admission program'
           when m.lvl in ('doctorate','masters_research') then 'research degree: Table 1 research rule is not tied to a named program'
           when m.k ~ '/' or m.k ~ ' and (bachelor|master|doctor|graduate|diploma|associate) (of|in) ' then 'double degree: the policy has no double-degree rule'
           when m.close then 'close to a Table 1 program name: review'
           else null end rs
      from m)
  select p.id, p.cricos, p.t, p.lvl, p.pl, p.rs,
         case when p.pl='table1' then p.exact->0->>'name' end,
         case when p.pl='table1' then p.exact->0->'reqs' when p.pl='minimum' then p_minimum end,
         p.ex,
         case when p.pl not in ('table1','minimum') then null
              when p.ex='{}'::jsonb then 'none'
              when exists(select 1 from jsonb_array_elements(case when p.pl='table1' then p.exact->0->'reqs' else p_minimum end) q
                           where p.ex ? (q->>'test_code') and (p.ex->>(q->>'test_code'))::numeric<>(q->>'overall_score')::numeric) then 'differs'
              when exists(select 1 from jsonb_array_elements(case when p.pl='table1' then p.exact->0->'reqs' else p_minimum end) q where p.ex ? (q->>'test_code')) then 'agrees'
              else 'other_tests_only' end
    from p;
end $f$;
revoke all on function security.english_table_plan_v1(text,jsonb,jsonb) from public, anon, authenticated;
