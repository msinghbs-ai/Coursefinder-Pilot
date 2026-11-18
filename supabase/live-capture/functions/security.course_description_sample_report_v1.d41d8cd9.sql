CREATE OR REPLACE FUNCTION security.course_description_sample_report_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with ids as (select * from security.course_description_sample_ids_v1()),
  pool as (select p.country, count(*) n from security.course_description_sample_pool_v1() p group by 1),
  strata as (select upper(x) code, o from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'enrich.course_description_sample_countries'), '[]'::jsonb)) with ordinality t(x, o)),
  claim as (select w from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'enrich.course_description_claim_words'), security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb)) w),
  dcn as (select distinct on (d.review_item_id) d.review_item_id, d.action, d.reason, coalesce(d.layer2_state->>'actor_kind', '') = 'machine' by_machine from pipeline.layer4_decisions d order by d.review_item_id, d.created_at desc),
  rws as (
    select ids.item_id, ids.country, ids.pick, i.status, dcn.action, dcn.reason, coalesce(dcn.by_machine, false) by_machine,
           case when i.status in ('rejected', 'more_evidence', 'returned_layer2', 'returned_layer3')
                then coalesce(substring(dcn.reason from '^\s*\[(identity|support|marketing|fragment|other)\]'), 'unclassified') end reason_class,
           coalesce(pv.display_name, pv.canonical_name) provider, coalesce(nullif(c.display_title, ''), c.canonical_title) course, g.identity_basis, g.url page_url,
           i.proposed_value->>'description' description,
           (select min(security.pdesc_support_v1(s->>'text', s->>'quote')) from jsonb_array_elements(coalesce(i.proposed_value->'sentences', '[]'::jsonb)) s) min_support,
           (select coalesce(jsonb_agg(distinct claim.w), '[]'::jsonb) from claim, jsonb_array_elements(coalesce(i.proposed_value->'sentences', '[]'::jsonb)) s where security.pdesc_has_term_v1(s->>'text', claim.w)) claims,
           case when e.value is null then null else security.course_description_check_v1(c.id, e.value) end rules_now
      from ids join pipeline.layer4_review_items i on i.id = ids.item_id
      join catalogue.courses c on c.id = i.entity_id left join catalogue.providers pv on pv.id = c.provider_id
      left join pipeline.coverage_course_pages g on g.course_id = c.id
      left join pipeline.field_enrich_items e on e.id = case when coalesce(i.proposed_value->>'item_id', '') ~ '^\d+$' then (i.proposed_value->>'item_id')::bigint end
      left join dcn on dcn.review_item_id = i.id)
  select jsonb_build_object(
    'strata', coalesce((select jsonb_agg(jsonb_build_object('country', strata.code, 'wanted', security.pipeline_num_v1('enrich.course_description_sample_' || lower(strata.code), 0),
                          'eligible', coalesce(pool.n, 0), 'selected', (select count(*) from rws where rws.country = strata.code),
                          'shortfall', greatest(0, security.pipeline_num_v1('enrich.course_description_sample_' || lower(strata.code), 0) - (select count(*) from rws where rws.country = strata.code))) order by strata.o)
                          from strata left join pool on pool.country = strata.code), '[]'::jsonb),
    'selected', (select count(*) from rws),
    'pending', (select count(*) from rws where rws.status = 'pending'),
    'approved', (select count(*) from rws where rws.status in ('approved', 'edited_approved') and not rws.by_machine),
    'approved_by_machine', (select count(*) from rws where rws.status in ('approved', 'edited_approved') and rws.by_machine),
    'rejected', (select count(*) from rws where rws.reason_class is not null),
    'approval_share_of_decided', (select round((count(*) filter (where rws.status in ('approved', 'edited_approved') and not rws.by_machine))::numeric / nullif(count(*) filter (where rws.status <> 'pending' and not rws.by_machine), 0), 3) from rws),
    'rejected_by_class', coalesce((select jsonb_object_agg(z.reason_class, z.n) from (select rws.reason_class, count(*) n from rws where rws.reason_class is not null group by 1) z), '{}'::jsonb),
    'reviewer_disagreement', jsonb_build_object(
        'passed_every_check_but_rejected', (select count(*) from rws where rws.reason_class is not null),
        'approved_but_rules_now_fail', (select count(*) from rws where rws.status in ('approved', 'edited_approved') and not rws.by_machine and rws.rules_now is not null and not coalesce((rws.rules_now->>'ok')::boolean, false))),
    'claim_support', jsonb_build_object('with_claim_words_in_quote', (select count(*) from rws where jsonb_array_length(rws.claims) > 0), 'lowest_sentence_support', (select min(rws.min_support) from rws)),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('ref', rws.item_id, 'country', rws.country, 'provider', rws.provider, 'course', rws.course, 'status', rws.status,
                        'reason_class', rws.reason_class, 'reason', rws.reason, 'min_support', rws.min_support, 'claims', rws.claims, 'identity_basis', rws.identity_basis,
                        'page_url', rws.page_url, 'description', rws.description, 'rules_now', rws.rules_now) order by rws.country, rws.pick) from rws), '[]'::jsonb),
    'note', 'A measurement of what the checks let through, decided by a person in Layer 4. It is not an authority to bypass Layer 4 and does not change enrich.course_description_review_first.')
$function$
