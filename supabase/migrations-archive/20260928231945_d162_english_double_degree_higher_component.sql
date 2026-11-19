-- CF-247 Decision 162 step 4 (Platform Admin approval 29 Sep 2026: trial "higher component wins" for double degrees).
-- UQ's ELP Procedure has no double-degree rule; UQ course pages show a double degree taking the higher requirement
-- of its component programs. Rule higher_component_v1, applied only when the source metadata switches it on:
--   * the title is split into its component programs;
--   * every component must be an exact Table 1 program or an existing UQ single program that takes the minimum,
--     otherwise the double degree stays held ("component not recognised");
--   * one Table 1 component -> that Table 1 requirement; none -> the minimum; two Table 1 components with different
--     requirements -> held.
-- While the rule is off the plan reports what it would do ("double degree trial: would take ...") with a
-- comparison against existing course-page values, and nothing is written. Apply notes name the double-degree rule.
do $g$ begin
  if (select md5(prosrc) from pg_proc where oid='security.english_table_plan_v1(text,jsonb,jsonb)'::regprocedure)<>'03a326332882761ef326106da8d4664a' then
    raise exception 'security.english_table_plan_v1 changed since review; not replaced'; end if;
end $g$;

create or replace function security.english_table_plan_v1(p_provider_cricos text, p_programs jsonb, p_minimum jsonb)
returns table(course_id uuid, course_cricos text, title text, study_level text, plan text, reason text, program text,
              requirements jsonb, existing jsonb, comparison text)
language plpgsql stable security definer set search_path to 'pg_catalog','catalogue','pipeline','ref','security' as $f$
declare v_provider uuid; v_aliases jsonb; v_double text;
begin
  select s.provider_id, coalesce(s.metadata->'aliases','{}'::jsonb), s.metadata->>'double_degree_rule' into v_provider, v_aliases, v_double from pipeline.sources s
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
      from m),
  dd as materialized (
    select p.id, comp.ord, btrim(comp.c) c,
           (select t1.reqs from t1 where t1.k=btrim(comp.c) limit 1) t1reqs,
           (select t1.name from t1 where t1.k=btrim(comp.c) limit 1) t1name,
           exists(select 1 from p p2 where p2.k=btrim(comp.c) and p2.pl='minimum') single_min
      from p, regexp_split_to_table(p.k,'/| and (?=(bachelor|master|doctor|graduate|diploma|associate) (of|in) )') with ordinality comp(c,ord)
     where p.rs='double degree: the policy has no double-degree rule'),
  ddr as materialized (
    select dd.id,
           bool_and(dd.t1reqs is not null or dd.single_min) all_known,
           string_agg(dd.c,'; ' order by dd.ord) filter (where dd.t1reqs is null and not dd.single_min) unknown,
           count(distinct dd.t1reqs) n_t1,
           (array_agg(dd.t1reqs order by dd.ord) filter (where dd.t1reqs is not null))[1] reqs,
           string_agg(dd.t1name,' + ' order by dd.ord) filter (where dd.t1name is not null) t1names
      from dd group by dd.id),
  q as materialized (
    select p.*,
      case when ddr.id is null then p.pl
           when not ddr.all_known or ddr.n_t1>1 then 'held'
           when v_double='higher_component_v1' then case when ddr.n_t1=1 then 'table1' else 'minimum' end
           else 'held' end pl2,
      case when ddr.id is null then p.rs
           when not ddr.all_known then 'double degree: component not recognised ('||ddr.unknown||')'
           when ddr.n_t1>1 then 'double degree: components carry different Table 1 requirements'
           when v_double='higher_component_v1' then 'double degree: higher component ('||case when ddr.n_t1=1 then 'Table 1: '||ddr.t1names else 'minimum' end||')'
           else 'double degree trial: would take '||case when ddr.n_t1=1 then 'Table 1 ('||ddr.t1names||')' else 'the minimum' end end rs2,
      case when ddr.id is null then case when p.pl='table1' then p.exact->0->>'name' end
           when ddr.all_known and ddr.n_t1=1 then ddr.t1names end prog2,
      case when ddr.id is null then case when p.pl='table1' then p.exact->0->'reqs' when p.pl='minimum' then p_minimum end
           when ddr.all_known and ddr.n_t1<=1 then coalesce(ddr.reqs,p_minimum) end reqs2
      from p left join ddr on ddr.id=p.id)
  select q.id, q.cricos, q.t, q.lvl, q.pl2, q.rs2, q.prog2, q.reqs2, q.ex,
         case when q.reqs2 is null then null
              when q.ex='{}'::jsonb then 'none'
              when exists(select 1 from jsonb_array_elements(q.reqs2) r
                           where q.ex ? (r->>'test_code') and (q.ex->>(r->>'test_code'))::numeric<>(r->>'overall_score')::numeric) then 'differs'
              when exists(select 1 from jsonb_array_elements(q.reqs2) r where q.ex ? (r->>'test_code')) then 'agrees'
              else 'other_tests_only' end
    from q;
end $f$;
revoke all on function security.english_table_plan_v1(text,jsonb,jsonb) from public, anon, authenticated;

do $patch$
declare v_def text; v_old text; v_new text;
begin
  v_def:=pg_get_functiondef('public.svc_english_table_apply(text,jsonb,jsonb,jsonb,jsonb)'::regprocedure);
  if (select md5(prosrc) from pg_proc where oid='public.svc_english_table_apply(text,jsonb,jsonb,jsonb,jsonb)'::regprocedure)<>'b9437183747791ae35902825352be250' then
    raise exception 'public.svc_english_table_apply changed since review; not replaced'; end if;
  v_old:=$o$'notes',case when r.plan='table1' then$o$;
  v_new:=$n$'notes',case when r.reason like 'double degree:%' then 'Decision 162: UQ '||r.reason when r.plan='table1' then$n$;
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1 then raise exception 'notes anchor not found exactly once'; end if;
  execute replace(v_def,v_old,v_new);
end $patch$;
