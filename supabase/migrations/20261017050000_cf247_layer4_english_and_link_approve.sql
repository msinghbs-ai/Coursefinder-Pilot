-- CF-247 (17 Oct 2026): Layer 4 approvals for English and course links. Platform Admin 17 Oct 2026 16:19: "Bring everything from layer 4 and
-- assess either for rule or ai extraction and proceed or give me recomemded choices".
-- Found while settling the 440 waiting items:
-- 1 Approving an English item (course_english) always failed ("field is not enabled for scalar Layer 4 editing"): no English item had ever been
--   approved in Layer 4. Approve and Edit and approve now write the English requirement: each test in the decided value is written for the
--   course (key l4:<item>:<test>, the item's evidence, notes with the reviewer's reason) and the course's English is locked as a person's
--   decision (Decision 181: a person's entry always wins). Other tests the course holds are kept.
-- 2 Approving a course link failed when the proposed page was stored as course_url (all 244 "course page that shows the CRICOS code" items);
--   the link apply now reads url or course_url.
-- Replaces: security.layer4_review_decide_impl and security.layer4_course_link_apply_impl (same names, md5-guarded)
-- Retires: nothing
-- Nothing dropped or deleted.

do $guard$
begin
  if md5(pg_get_functiondef('security.layer4_review_decide_impl(uuid,text,text,jsonb)'::regprocedure)) <> 'dae40e946183598c2e6a4be9843d16fb' then
    raise exception 'live security.layer4_review_decide_impl differs from the definition this change replaces';
  end if;
  if md5(pg_get_functiondef('security.layer4_course_link_apply_impl(uuid,uuid,jsonb,text)'::regprocedure)) <> '5b9c4ce104f96ba4136a3ad2e8f8440e' then
    raise exception 'live security.layer4_course_link_apply_impl differs from the definition this change replaces';
  end if;
end $guard$;

create or replace function security.layer4_course_english_apply_impl(p_actor uuid, p_item_id uuid, p_value jsonb, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_item pipeline.layer4_review_items%rowtype; x jsonb; v_test uuid; v_n int := 0; v_src uuid;
begin
  select * into v_item from pipeline.layer4_review_items where id = p_item_id;
  if v_item.entity_type <> 'course' then raise exception 'English requirements apply to courses only'; end if;
  if jsonb_typeof(p_value->'english_requirements') <> 'array' or jsonb_array_length(p_value->'english_requirements') = 0 then
    raise exception 'enter at least one English test score, then approve';
  end if;
  select id into v_src from pipeline.sources where source_type = 'layer4_human_review' limit 1;
  for x in select e from jsonb_array_elements(p_value->'english_requirements') e loop
    select id into v_test from ref.english_tests where code = upper(btrim(coalesce(x->>'test_code', x->>'test')));
    if v_test is null then raise exception 'unknown English test %', coalesce(x->>'test_code', x->>'test'); end if;
    if coalesce(x->>'overall_score', x->>'overall', '') !~ '^[0-9]+(\.[0-9]+)?$' then raise exception 'enter an overall score for %', coalesce(x->>'test_code', x->>'test'); end if;
    insert into catalogue.course_english_requirements(course_id, english_test_id, overall_score, component_scores, notes, source_id, evidence_id, confidence,
                                                      source_requirement_key, status, last_verified_at)
    values (v_item.entity_id, v_test, coalesce(x->>'overall_score', x->>'overall')::numeric, coalesce(x->'component_scores', x->'components', '{}'::jsonb),
            'Layer 4 decision: ' || p_reason, v_src, v_item.evidence_id, 1, 'l4:' || v_item.id || ':' || lower(coalesce(x->>'test_code', x->>'test')), 'active', now())
    on conflict (course_id, english_test_id) do update set overall_score = excluded.overall_score, component_scores = excluded.component_scores, notes = excluded.notes,
           source_id = excluded.source_id, evidence_id = excluded.evidence_id, confidence = 1, source_requirement_key = excluded.source_requirement_key,
           status = 'active', last_verified_at = now();
    v_n := v_n + 1;
  end loop;
  insert into pipeline.manual_locks(entity, entity_id, field, mode, set_by) values ('course', v_item.entity_id, 'english', 'value', p_actor)
  on conflict (entity, entity_id, field) do update set mode = excluded.mode, set_by = excluded.set_by, set_at = now();
  perform search.refresh_course_enrichment_scoped_v1(array[v_item.entity_id], true);
  return jsonb_build_object('tests_written', v_n, 'search_refreshed', true);
end $function$;
revoke execute on function security.layer4_course_english_apply_impl(uuid, uuid, jsonb, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION security.layer4_review_decide_impl(p_review_item_id uuid, p_action text, p_reason text, p_final_value jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'auth'
AS $function$
declare
  v_actor uuid:=auth.uid(); v_rank int; v_item pipeline.layer4_review_items%rowtype;
  v_final jsonb; v_state text; v_scalar jsonb; v_scalar_id uuid; v_decision uuid;
  v_refresh_id uuid; v_search_signal_id uuid; v_evidence pipeline.evidence_artifacts%rowtype;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
  if p_action not in ('approve','edit_and_approve','reject','request_more_evidence','return_layer2','return_layer3') then
    raise exception 'invalid action';
  end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'decision reason required'; end if;

  select * into v_item from pipeline.layer4_review_items where id=p_review_item_id for update;
  if not found then raise exception 'review item not found'; end if;
  if v_item.status<>'pending' then raise exception 'review item already decided'; end if;
  select * into v_evidence from pipeline.evidence_artifacts where id=v_item.evidence_id;

  v_final:=case when p_action='approve' then v_item.proposed_value when p_action='edit_and_approve' then p_final_value else null end;
  if p_action='edit_and_approve' and p_final_value is null then raise exception 'edited final value required'; end if;

  if p_action in ('approve','edit_and_approve') then
    if v_item.field_code='provider_current_tuition_validation' then
      -- Layer 4 tuition decisions record the fee (same convention as Layer 3 admission).
      v_scalar:=security.layer4_tuition_apply_impl(v_actor,v_item.id,v_final,trim(p_reason));
      v_scalar_id:=null;
    elsif v_item.field_code='official_course_url' then
      v_scalar:=security.layer4_course_link_apply_impl(v_actor,v_item.id,v_final,trim(p_reason));
      v_scalar_id:=null;
    elsif v_item.field_code='course_english' then
      -- CF-247 17 Oct 2026: English decisions write the course's English requirement (it was refused before)
      v_scalar:=security.layer4_course_english_apply_impl(v_actor,v_item.id,v_final,trim(p_reason));
      v_scalar_id:=null;
    elsif v_item.entity_type='scholarship' and v_item.field_code='scope_resolution' then
      v_scalar:=security.layer4_scholarship_scope_close_impl(v_item.id);
      v_scalar_id:=null;
    else
    if v_item.entity_type<>'course' then raise exception 'terminal apply currently supports course scalar facts only'; end if;
    v_scalar:=security.layer4_course_scalar_resolve_impl(v_actor,v_item.entity_id,v_item.field_code,v_final,trim(p_reason));
    v_scalar_id:=nullif(v_scalar->>'resolution_id','')::uuid;
    end if;
    v_state:=case when p_action='approve' then 'approved' else 'edited_approved' end;
  elsif p_action='reject' then v_state:='rejected';
  elsif p_action='request_more_evidence' then v_state:='more_evidence';
  elsif p_action='return_layer2' then v_state:='returned_layer2';
  else v_state:='returned_layer3'; end if;

  update pipeline.layer4_review_items set status=v_state,decided_at=now() where id=v_item.id;
  insert into pipeline.layer4_decisions(
    review_item_id,action,actor_id,reason,before_value,proposed_value,final_value,evidence_id,
    layer2_state,layer3_state,scalar_resolution_id,change_control_ref
  ) values (
    v_item.id,p_action,v_actor,trim(p_reason),v_item.before_value,v_item.proposed_value,v_final,
    v_item.evidence_id,v_item.layer2_state,v_item.layer3_state,v_scalar_id,v_item.change_control_ref
  ) returning id into v_decision;

  if p_action in ('request_more_evidence','return_layer2') then
    insert into pipeline.refresh_requests(
      requested_layer,source_id,entity_type,entity_id,evidence_id,reason,trigger_type,requested_by,change_control_ref
    ) values (
      2,v_evidence.source_id,v_item.entity_type,v_item.entity_id,v_item.evidence_id,trim(p_reason),
      'layer4_return',v_actor,v_item.change_control_ref
    ) returning id into v_refresh_id;
  elsif p_action='return_layer3' then
    insert into pipeline.refresh_requests(
      requested_layer,source_id,entity_type,entity_id,evidence_id,layer3_profile_id,revalidation_ref,
      reason,trigger_type,requested_by,change_control_ref
    ) values (
      3,v_evidence.source_id,v_item.entity_type,v_item.entity_id,v_item.evidence_id,
      nullif(v_item.layer3_state->>'profile_id','')::uuid,
      'L4:'||v_decision::text,trim(p_reason),'layer4_return',v_actor,v_item.change_control_ref
    ) returning id into v_refresh_id;
  end if;

  if p_action in ('approve','edit_and_approve') then
    insert into pipeline.search_refresh_signals(
      entity_type,entity_id,review_decision_id,reason,change_control_ref
    ) values (
      v_item.entity_type,v_item.entity_id,v_decision,
      'Accepted Layer 4 canonical change: '||trim(p_reason),v_item.change_control_ref
    ) returning id into v_search_signal_id;
  end if;

  return jsonb_build_object(
    'ok',true,'decision_id',v_decision,'review_item_id',v_item.id,'action',p_action,'status',v_state,
    'final_value',v_final,'scalar_resolution_id',v_scalar_id,'refresh_request_id',v_refresh_id,
    'publication_changed',false,'search_refresh_required',v_search_signal_id is not null,
    'search_refresh_signal_id',v_search_signal_id
  );
end $function$;

CREATE OR REPLACE FUNCTION security.layer4_course_link_apply_impl(p_actor uuid, p_item_id uuid, p_value jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'pipeline', 'search'
AS $function$
declare v_item pipeline.layer4_review_items%rowtype; v_url text; v_host text; v_link uuid;
begin
  select * into v_item from pipeline.layer4_review_items where id=p_item_id;
  if v_item.entity_type<>'course' then raise exception 'course links apply to courses only'; end if;
  -- CF-247 17 Oct 2026: the proposed page may be stored as url or course_url
  v_url := btrim(coalesce(case jsonb_typeof(p_value) when 'string' then p_value#>>'{}' when 'object' then coalesce(p_value->>'url', p_value->>'course_url') end,
                          case jsonb_typeof(v_item.proposed_value) when 'string' then v_item.proposed_value#>>'{}' when 'object' then coalesce(v_item.proposed_value->>'url', v_item.proposed_value->>'course_url') end,''));
  if v_url='' then raise exception 'enter the official course page link, then approve'; end if;
  if v_url !~* '^https://[a-z0-9.-]+\.[a-z]{2,}(/[^\s]*)?$' then raise exception 'the link must be a full https:// web address'; end if;
  v_host := lower(substring(v_url from '^https://([^/]+)'));
  if security.reference_url_has_use(v_url, 'not_course_page') then
    raise exception 'use the provider''s own course page, not a search, social or course-listing site (%)', v_host;
  end if;
  insert into catalogue.course_links(course_id,link_type,url,audience,label,is_primary,status,source_id,evidence_id,confidence,last_verified_at,updated_at)
  values (v_item.entity_id,'official_course',v_url,'international','Official provider course page (confirmed by reviewer)',false,'active',(select id from pipeline.sources where source_type='layer4_human_review' limit 1),v_item.evidence_id,1,now(),now())
  on conflict(course_id,link_type,url) do update set label=excluded.label,status='active',source_id=excluded.source_id,confidence=1,last_verified_at=now(),updated_at=now()
  returning id into v_link;
  perform search.refresh_course_enrichment_scoped_v1(array[v_item.entity_id], true);
  return jsonb_build_object('course_link_id',v_link,'url',v_url,'search_refreshed',true);
end $function$;

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'security.layer4_course_english_apply_impl', 'Layer 4', 'Writes a course''s English requirement decided in Layer 4 (a person''s decision, locked)', 'active', '20261017050000')
on conflict (kind, name) do nothing;
