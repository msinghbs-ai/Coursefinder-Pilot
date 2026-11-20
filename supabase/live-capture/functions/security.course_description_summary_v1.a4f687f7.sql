CREATE OR REPLACE FUNCTION security.course_description_summary_v1(p_provider uuid DEFAULT NULL::uuid, p_recheck boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with r as (select * from security.course_description_reconcile_v1(p_provider, p_recheck, security.pipeline_num_v1('enrich.course_description_report_max', 500)::int)),
  cls as (select r.class, count(*) n from r group by 1),
  cty as (select coalesce(r.country, '?') country, count(*) n, count(*) filter (where r.class = 'ready') ready from r group by 1),
  l4 as (
    select i.id, i.status, c.id course_id, i.proposed_value->>'description' d, nullif(btrim(c.description), '') cur, exists (select 1 from pipeline.layer4_decisions md where md.review_item_id = i.id and md.layer2_state->>'actor_kind' = 'machine') by_machine
      from pipeline.layer4_review_items i join catalogue.courses c on c.id = i.entity_id
     where i.entity_type = 'course' and i.field_code = 'course_description_first_read' and (p_provider is null or c.provider_id = p_provider)),
  fe as (select f.* from pipeline.field_enrich_items f where f.field = 'description' and (p_provider is null or f.provider_id = p_provider))
  select jsonb_build_object(
    'provider_id', p_provider,
    'pending', (select count(*) from r),
    'by_class', coalesce((select jsonb_object_agg(cls.class, cls.n) from cls), '{}'::jsonb),
    'by_country', coalesce((select jsonb_object_agg(cty.country, jsonb_build_object('pending', cty.n, 'ready', cty.ready)) from cty), '{}'::jsonb),
    'rechecked', (select count(*) from r where r.rechecked),
    'oldest', (select min(r.created_at) from r),
    -- the four measures, never mixed: an AI reading waiting in Layer 4 is neither admitted nor published
    'proposed_in_layer4', (select count(*) from l4 where l4.status = 'pending'),
    'waiting_behind_provider_cap', (select count(*) from fe where fe.state = 'skipped' and fe.reason like 'held\_first\_admission:%'),
    'admitted_by_person', (select count(*) from l4 where l4.status in ('approved', 'edited_approved') and not l4.by_machine and l4.cur is not distinct from nullif(btrim(l4.d), '')),
    'admitted_by_machine', (select count(*) from l4 where l4.status in ('approved', 'edited_approved') and l4.by_machine and l4.cur is not distinct from nullif(btrim(l4.d), '')),
    'admitted_without_a_person', (select count(*) from fe where fe.state = 'filled' and coalesce(fe.value->>'admitted', '') <> ''),
    'published_to_the_website', (select count(distinct l4.course_id) from l4 join search.course_documents sd on sd.course_id = l4.course_id
                                   where l4.status in ('approved', 'edited_approved') and l4.cur is not distinct from nullif(btrim(l4.d), '') and nullif(btrim(sd.description), '') = l4.cur
                                     and sd.publication_status = 'published'
                                     and not exists (select 1 from security.layer4_search_blocked_courses b where b.course_id = l4.course_id)),
    'decided', (select jsonb_object_agg(z.status, z.n) from (select l4.status, count(*) n from l4 group by 1) z),
    'limits', jsonb_build_object('min_sentences', security.pipeline_num_v1('enrich.course_description_min_sentences', 1), 'max_sentences', security.pipeline_num_v1('enrich.course_description_max_sentences', 4),
                                 'min_chars', security.pipeline_num_v1('enrich.course_description_min_chars', 80), 'max_chars', security.pipeline_num_v1('enrich.course_description_max_chars', 700)),
    'reask_max', security.pipeline_num_v1('enrich.course_description_reask_max', 0),
    'review_first', security.pipeline_num_v1('enrich.course_description_review_first', 100000),
    'note', 'Measurement only. A person admits every description in Layer 4 except those the machine rule admits (counted apart as admitted_by_machine); nothing here admits, decides or changes a setting.')
$function$
