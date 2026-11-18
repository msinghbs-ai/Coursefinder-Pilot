CREATE OR REPLACE FUNCTION security.course_description_pack_v1(p_provider uuid DEFAULT NULL::uuid, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with cfg as (
    select coalesce(security.toolset_setting('pipeline', 'enrich.course_description_claim_words'), security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb) claim,
           coalesce(security.toolset_setting('pipeline', 'enrich.course_description_marketing_words'), security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb) mkt),
  r as (select q.* from security.course_description_reconcile_v1(p_provider, false, 0) q where q.class = 'ready'),
  t as (
    select r.*, i.escalation_reason, i.before_value, i.proposed_value, i.evidence_id ev_id, c.course_code, pv.display_name pname, pv.canonical_name pcanon,
           btrim(i.proposed_value ->> 'description') d, md5(btrim(i.proposed_value ->> 'description')) h
      from r join pipeline.layer4_review_items i on i.id = r.item_id join catalogue.courses c on c.id = r.course_id left join catalogue.providers pv on pv.id = r.provider_id),
  same as (select h, count(*) n from t group by h),
  pub as (select md5(btrim(c.description)) h, count(*) n from catalogue.courses c where nullif(btrim(c.description), '') is not null group by 1),
  held as (select e.provider_id, count(*) n from pipeline.field_enrich_items e where e.field = 'description' and e.state = 'skipped' and e.reason like 'held_first_admission:%' group by 1),
  pc as (select provider_id, count(*) n from t group by 1),
  f as (
    select t.*, coalesce(hd.n, 0) unlock, pc.n in_university,
           (coalesce(same.n, 1) - 1) + coalesce(pub.n, 0) shared_n,
           exists (select 1 from jsonb_array_elements_text(cfg.claim) w where security.pdesc_has_term_v1(t.d, w)) has_claim,
           exists (select 1 from jsonb_array_elements_text(cfg.mkt) w where security.pdesc_has_term_v1(t.d, w)) has_mkt,
           t.d ~ '(\$|AUD|NZD|CAD)|\m(19|20)[0-9]{2}\M' has_fact
      from t cross join cfg left join same on same.h = t.h left join pub on pub.h = t.h left join held hd on hd.provider_id = t.provider_id left join pc on pc.provider_id = t.provider_id),
  g as (
    select f.*, array_remove(array[case when shared_n > 0 then 'same_words_elsewhere' end, case when has_claim then 'claim_word' end,
                                    case when has_mkt then 'marketing_word' end, case when has_fact then 'money_or_year' end], null) flags
      from f),
  o as (
    select g.*, dense_rank() over (order by g.unlock desc, g.in_university desc, coalesce(g.pname, g.pcanon), g.provider_id) prank,
           row_number() over (order by g.unlock desc, g.in_university desc, coalesce(g.pname, g.pcanon), g.provider_id, cardinality(g.flags), g.created_at, g.item_id) rn
      from g),
  pg as (select o.* from o where o.rn > greatest(coalesce(p_offset, 0), 0) and o.rn <= greatest(coalesce(p_offset, 0), 0) + security.pipeline_num_v1('layer4.inbox_page_size', 25)::int)
  select jsonb_build_object(
    'total', (select count(*) from o), 'offset', greatest(coalesce(p_offset, 0), 0), 'limit', security.pipeline_num_v1('layer4.inbox_page_size', 25)::int,
    'order', 'universities whose decision frees the most held readings first, then the larger queue; within a university the items with no flag first, then oldest',
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'kind', 'provider_description', 'ref', pg.item_id::text, 'provider_id', pg.provider_id, 'provider', coalesce(pg.pname, pg.pcanon), 'subject', pg.course_title,
        'why', coalesce(nullif(pg.escalation_reason, ''), 'Needs a decision'), 'created_at', pg.created_at, 'ready', true,
        'detail', jsonb_strip_nulls(jsonb_build_object('field_code', 'course_description_first_read', 'course_id', pg.course_id, 'course_code', pg.course_code,
                    'code_label', case when pg.country = 'AU' then 'CRICOS' else 'Course code' end,
                    'before', pg.before_value, 'proposed', pg.proposed_value, 'evidence_id', pg.ev_id, 'captured_at', ev.captured_at, 'source_url', ev.source_url,
                    'reask', pg.reask,
                    'pack', jsonb_build_object('flags', to_jsonb(pg.flags), 'flag_count', cardinality(pg.flags), 'same_words_on_other_courses', pg.shared_n,
                                               'held_readings_this_decision_can_free', pg.unlock, 'waiting_in_university', pg.in_university, 'university_rank', pg.prank))))
        order by pg.rn)
      from pg left join pipeline.evidence_artifacts ev on ev.id = pg.ev_id), '[]'::jsonb))
$function$
