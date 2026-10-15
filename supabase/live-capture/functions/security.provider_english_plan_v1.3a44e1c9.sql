CREATE OR REPLACE FUNCTION security.provider_english_plan_v1(p_proposal_id uuid)
 RETURNS TABLE(course_id uuid, title text, study_level text, plan text, reason text, requirements jsonb, existing jsonb, outcome text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'ref', 'security'
AS $function$
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
                when c0.lvl in ('graduate_certificate', 'graduate_diploma', 'masters', 'masters_coursework', 'masters_extended') then 'postgraduate'
                when c0.lvl in ('doctorate', 'masters_research') then 'research' end grp,  -- CF-247 15 Oct: research degrees take the policy's research default
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
                when m.lvl in ('doctorate', 'masters_research') and jsonb_typeof(v_defaults->'research') is distinct from 'array' then 'held|research degree (the policy states no research requirement)'
                when m.t ~* 'exit award' then 'held|exit award only'
                when (m.k ~ '/' or m.k ~ ' and (bachelor|master|doctor|graduate|diploma|associate) (of|in) ') and not security.double_degree_same_group_v1(m.t, m.grp) then 'held|double degree (its parts are at different levels)'
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
end $function$
