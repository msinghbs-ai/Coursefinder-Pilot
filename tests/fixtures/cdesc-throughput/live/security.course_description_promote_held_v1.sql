create or replace function security.course_description_promote_held_v1(p_provider uuid) returns integer language plpgsql security definer set search_path to '' as $function$
declare r record; v_n int := 0; v_slots int; v_chk jsonb; v_review uuid; v_text text;
begin
  if p_provider is null or security.pipeline_num_v1('enrich.course_description_promote_held_on', 1) < 1 then return 0; end if;
  if security.course_description_trusted_v1(p_provider) then return 0; end if;
  v_slots := security.pipeline_num_v1('enrich.course_description_pending_max', 10)::int
           - (select count(*) from pipeline.layer4_review_items q join catalogue.courses c on c.id = q.entity_id
               where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending' and c.provider_id = p_provider);
  if v_slots <= 0 then return 0; end if;
  for r in select e.id, e.course_id, e.value, e.quote, g.evidence_id, g.url, g.identity_basis, g.provider_id
             from pipeline.field_enrich_items e join pipeline.coverage_course_pages g on g.course_id = e.course_id
            where e.provider_id = p_provider and e.field = 'description' and e.state = 'skipped' and e.reason like 'held_first_admission:%'
              and nullif(btrim(e.value->>'text'), '') is not null and e.evidence_id is not distinct from g.evidence_id
            order by e.id
              for update of e skip locked loop
    exit when v_n >= v_slots;
    continue when not security.coverage_identity_allowed(r.provider_id, r.identity_basis, 'description');
    continue when exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = r.course_id and l.field in ('description', 'course_description', 'all'));
    continue when exists (select 1 from catalogue.courses c where c.id = r.course_id and nullif(btrim(c.description), '') is not null);
    continue when exists (select 1 from pipeline.layer4_review_items q where q.entity_type = 'course' and q.entity_id = r.course_id
                           and q.field_code = 'course_description_first_read' and q.status = 'pending');
    v_chk := security.course_description_check_v1(r.course_id, r.value);
    continue when not coalesce((v_chk->>'ok')::boolean, false);
    v_text := v_chk->>'text';
    insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
    values ('course', r.course_id, 'course_description_first_read', r.evidence_id, jsonb_build_object('description', null),
            jsonb_build_object('description', v_text, 'item_id', r.id, 'source_url', r.url, 'checks', v_chk->'checks',
                               'sentences', (select jsonb_agg(jsonb_build_object('text', s->>'text', 'quote', s->>'quote') order by o) from jsonb_array_elements(r.value->'sentences') with ordinality e(s, o))),
            jsonb_build_object('source', 'course description reader', 'page', r.url, 'identity_basis', r.identity_basis),
            jsonb_build_object('item_id', r.id, 'held_first_admission', true),
            'pending', 'Course description read from the course''s own page. This is one of the provider''s first course descriptions, so a person approves it as read or rejects it.',
            'CF-CHG-20260915-247')
    returning id into v_review;
    update pipeline.field_enrich_items set state = 'review', reason = null, value = r.value || jsonb_build_object('review_item_id', v_review, 'promoted_from', 'held_first_admission'), updated_at = now()
     where id = r.id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;
