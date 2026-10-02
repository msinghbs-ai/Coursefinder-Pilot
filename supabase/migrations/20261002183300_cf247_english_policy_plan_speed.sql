-- CF-247 (Decision 227 follow-up, 2 Oct 2026). Found in the live check after release v2.15.153: the English policies
-- list worked out every university's course-by-course plan each time it was opened (34 seconds for 44 policies), and
-- approving a large policy wrote all its courses at once (15 seconds for Flinders' 197). Both exceed the 8-second limit
-- on a signed-in request, so the panel would not load and a large approval would fail.
--  * The plan is faster: title words are worked out once per course and once per name in the policy (same rule as
--    security.english_title_overlap: shared words over the larger word count, at least 0.75).
--  * Each policy's plan counts are kept with the policy and refreshed every 10 minutes (and when a policy is approved);
--    the list shows the kept counts and when they were worked out.
--  * Approving records the decision and checks agreement on fresh counts; the courses are filled by the job within 10
--    minutes (job provider-english-defaults, now every 10 minutes), not in the approval request.
-- Function changes are behind md5 guards on the sources created by migrations 20261002183100 and 20261002183200.

do $g$
begin
  if (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.proname = 'provider_english_plan_v1')
     is distinct from '88e916ac773d57395ea81b992012afae' then raise exception 'security.provider_english_plan_v1 changed; not replacing'; end if;
end $g$;

create or replace function security.provider_english_plan_v1(p_proposal_id uuid)
returns table(course_id uuid, title text, study_level text, plan text, reason text, requirements jsonb, existing jsonb, outcome text)
language plpgsql stable security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'ref', 'security' as $f$
declare x pipeline.provider_policy_proposals%rowtype; v_named jsonb; v_defaults jsonb;
begin
  select * into x from pipeline.provider_policy_proposals where id = p_proposal_id;
  if x.id is null or x.kind <> 'english_policy' then raise exception 'not an English policy proposal'; end if;
  v_defaults := coalesce(x.proposal->'defaults', '{}'::jsonb);
  select coalesce(jsonb_agg(jsonb_build_object('k', s.k, 'reqs', s.reqs)), '[]'::jsonb) into v_named from (
    select security.english_title_key(n) k, null::jsonb reqs from jsonb_array_elements_text(coalesce(x.proposal->'named', '[]'::jsonb)) n
    union all
    select security.english_title_key(e->>'name'), case when jsonb_typeof(e->'reqs') = 'array' and jsonb_array_length(e->'reqs') > 0
                                                       then (select jsonb_agg(q - 'quote') from jsonb_array_elements(e->'reqs') q) end
      from jsonb_array_elements(coalesce(x.proposal->'exceptions', '[]'::jsonb)) e) s where length(s.k) >= 4;
  return query
  with named as materialized (
    select e->>'k' k, nullif(e->'reqs', 'null'::jsonb) reqs,
           array(select distinct t from unnest(regexp_split_to_array(e->>'k', '[ /]+')) t where t not in ('of', 'and', 'in', 'the', '')) toks
      from jsonb_array_elements(v_named) e),
  c0 as materialized (
    select co.id, co.canonical_title t, security.english_title_key(co.canonical_title) k, sl.code lvl
      from catalogue.courses co left join ref.study_levels sl on sl.id = co.study_level_id
     where co.provider_id = x.provider_id and co.lifecycle_status = 'active'),
  c as materialized (
    select c0.*, array(select distinct t from unnest(regexp_split_to_array(c0.k, '[ /]+')) t where t not in ('of', 'and', 'in', 'the', '')) toks,
           case when c0.lvl in ('bachelor', 'bachelor_honours', 'associate_degree') then 'undergraduate'
                when c0.lvl in ('graduate_certificate', 'graduate_diploma', 'masters', 'masters_coursework', 'masters_extended') then 'postgraduate' end grp,
           (select coalesce(jsonb_object_agg(et.code, r.overall_score), '{}'::jsonb) from catalogue.course_english_requirements r
              join ref.english_tests et on et.id = r.english_test_id where r.course_id = c0.id and r.status = 'active') ex,
           exists (select 1 from catalogue.course_english_requirements r where r.course_id = c0.id) any_row,
           exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c0.id and l.field in ('english', 'english_requirements', 'course_english')) locked,
           exists (select 1 from pipeline.layer4_review_items i where i.entity_type = 'course' and i.entity_id = c0.id and i.field_code = 'course_english' and i.status = 'pending') in_review,
           exists (select 1 from pipeline.layer3_fact_handoffs h left join pipeline.layer3_work_items w on w.id = h.work_item_id
                    where h.course_id = c0.id and h.task_class = 'provider_english_validation'
                      and (h.work_item_id is null or w.status in ('interpreting', 'validated', 'queued', 'pending'))) in_l3,
           exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c0.id and g.status in ('bound', 'ambiguous')
                      and (g.read_status is null or g.read_status = 'needs_render')) page_waiting
      from c0),
  m as (
    select c.*,
           (select jsonb_agg(distinct named.reqs) from named where named.k = c.k and named.reqs is not null) exact_reqs,
           exists (select 1 from named where named.k = c.k) exact_named,
           exists (select 1 from named where named.k <> c.k and (position(named.k in c.k) > 0 or position(c.k in named.k) > 0
                     or (cardinality(c.toks) > 0 and cardinality(named.toks) > 0
                         and (select count(*) from unnest(c.toks) t where t = any(named.toks))::numeric / greatest(cardinality(c.toks), cardinality(named.toks)) >= 0.75))) close_named,
           case when c.grp is not null then v_defaults->c.grp end dflt
      from c),
  p as (
    select m.*,
           case when m.lvl is null then 'held|study level unknown'
                when m.lvl in ('doctorate', 'masters_research') then 'held|research degree'
                when m.t ~* 'exit award' then 'held|exit award only'
                when m.k ~ '/' or m.k ~ ' and (bachelor|master|doctor|graduate|diploma|associate) (of|in) ' then 'held|double degree'
                when m.exact_reqs is not null and jsonb_array_length(m.exact_reqs) > 1 then 'held|the policy gives this course more than one requirement'
                when m.exact_reqs is not null then 'named|'
                when m.exact_named or m.close_named then 'held|named in the policy (it may have its own requirement)'
                when m.grp is null then 'held|level not covered by the policy default'
                when m.dflt is null or jsonb_typeof(m.dflt) <> 'array' then 'held|the policy gives no default for this level'
                else 'default|' end pr
      from m),
  q as (
    select p.*, split_part(p.pr, '|', 1) pl, nullif(split_part(p.pr, '|', 2), '') rs,
           case when p.pr like 'named|%' then p.exact_reqs->0 when p.pr like 'default|%' then p.dflt end reqs
      from p)
  select q.id, q.t, q.lvl, q.pl, q.rs, q.reqs, q.ex,
         case when q.pl = 'held' then 'held'
              when q.any_row and exists (select 1 from jsonb_array_elements(q.reqs) r where q.ex ? (r->>'test_code') and (q.ex->>(r->>'test_code'))::numeric <> (r->>'overall_score')::numeric) then 'differs'
              when q.any_row and exists (select 1 from jsonb_array_elements(q.reqs) r where q.ex ? (r->>'test_code')) then 'agrees'
              when q.any_row then 'other_value'
              when q.locked then 'set_by_hand'
              when q.in_review then 'in_review'
              when q.in_l3 or q.page_waiting then 'waiting'
              else 'write' end
    from q;
end $f$;
revoke all on function security.provider_english_plan_v1(uuid) from public, anon, authenticated;

-- kept plan counts
alter table pipeline.provider_policy_proposals add column if not exists plan_summary jsonb, add column if not exists plan_at timestamptz;

create or replace function security.provider_policy_refresh_one_v1(p_id uuid)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'pipeline', 'security' as $f$
declare v jsonb;
begin
  select coalesce(jsonb_object_agg(o, n), '{}'::jsonb) into v from (select r.outcome o, count(*) n from security.provider_english_plan_v1(p_id) r group by 1) s;
  update pipeline.provider_policy_proposals set plan_summary = v, plan_at = now() where id = p_id;
  return v;
end $f$;
revoke all on function security.provider_policy_refresh_one_v1(uuid) from public, anon, authenticated;

create or replace function security.provider_policy_refresh_plans_v1(p_limit integer default 12)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'pipeline', 'security' as $f$
declare r record; v_n int := 0;
begin
  for r in select id from pipeline.provider_policy_proposals
            where kind = 'english_policy' and status in ('proposed', 'approved') and (plan_at is null or plan_at < now() - interval '30 minutes')
            order by plan_at nulls first, created_at limit greatest(1, least(coalesce(p_limit, 12), 100)) loop
    perform security.provider_policy_refresh_one_v1(r.id); v_n := v_n + 1;
  end loop;
  return jsonb_build_object('refreshed', v_n);
end $f$;
revoke all on function security.provider_policy_refresh_plans_v1(integer) from public, anon, authenticated;

-- the list shows the kept counts
do $p$
declare s text; d text;
  o1 text := $o$'plan', case when x.kind = 'english_policy' and x.status in ('proposed', 'approved')
                      then (select jsonb_object_agg(o, n) from (select r.outcome o, count(*) n from security.provider_english_plan_v1(x.id) r group by 1) s) end)$o$;
  n1 text := $n$'plan', x.plan_summary, 'plan_at', x.plan_at)$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'admin_provider_policies_read';
  if md5(s) is distinct from 'a434ab85f12755c36523760e1634a9fa' then raise exception 'admin_provider_policies_read changed (md5 %); not replacing', md5(s); end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'piece not found once'; end if;
  execute replace(d, o1, n1);
end $p$;

-- approval: agreement checked on fresh counts; courses filled by the job, not in the request
do $p$
declare s text; d text;
  o1 text := $o$v_ag int := 0; v_df int := 0;$o$;
  n1 text := $n$v_ag int := 0; v_df int := 0; v_sum jsonb;$n$;
  o2 text := $o$    select count(*) filter (where r.outcome = 'agrees'), count(*) filter (where r.outcome = 'differs') into v_ag, v_df
      from security.provider_english_plan_v1(p_id) r;$o$;
  n2 text := $n$    v_sum := security.provider_policy_refresh_one_v1(p_id);
    v_ag := coalesce((v_sum->>'agrees')::int, 0); v_df := coalesce((v_sum->>'differs')::int, 0);$n$;
  o3 text := $o$if p_action = 'approve' and x.kind = 'english_policy' then v := security.provider_english_apply_v1(p_id); end if;$o$;
  n3 text := $n$if p_action = 'approve' and x.kind = 'english_policy' then v := jsonb_build_object('to_fill', coalesce((v_sum->>'write')::int, 0)); end if;$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'admin_provider_policy_decide';
  if md5(s) is distinct from '8922971933272730264bc8e4de099268' then raise exception 'admin_provider_policy_decide changed (md5 %); not replacing', md5(s); end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'piece 1 not found once'; end if;
  if (length(d) - length(replace(d, o2, ''))) / length(o2) <> 1 then raise exception 'piece 2 not found once'; end if;
  if (length(d) - length(replace(d, o3, ''))) / length(o3) <> 1 then raise exception 'piece 3 not found once'; end if;
  execute replace(replace(replace(d, o1, n1), o2, n2), o3, n3);
end $p$;

-- the job: refresh kept counts, then fill courses for approved policies, every 10 minutes
select cron.alter_job(j.jobid, schedule := '3-59/10 * * * *',
                      command := $c$select security.provider_policy_refresh_plans_v1(12); select security.provider_english_apply_all_v1();$c$)
  from cron.job j where j.jobname = 'provider-english-defaults';
update pipeline.automation_catalogue
   set description = 'Every 10 minutes: works out each English policy''s course-by-course plan, then gives courses the English requirement from their university''s approved policy (the course''s own requirement where the policy names it, otherwise the default for its level). Only courses with no English requirement, no review open and no page still to read; research, double degrees and courses the policy names are held back.'
 where jobname = 'provider-english-defaults';

-- first counts for the policies waiting now
select security.provider_policy_refresh_plans_v1(100);
