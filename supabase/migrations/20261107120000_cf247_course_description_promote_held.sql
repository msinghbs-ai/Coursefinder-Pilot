-- CF-247 course descriptions: a decision in Layer 4 lets the same provider's held readings take the freed place in the queue.
-- Guards: G2 (the cap is the existing setting enrich.course_description_pending_max), G3 (no consumer API object is touched), Decision 260 (housekeeping),
--   "No unauthorised Layer 4 admission" (Platform Admin P0 mandate 3 Nov 2026 10:44 section 7): this moves a stored reading into the PERSON's queue; it never
--   writes catalogue.courses.description, never decides an item and never changes review_first.
-- Replaces: security.course_description_review_trg_v1 (md5-guarded; the same settling and held-release steps, plus the promotion call)
-- Retires: nothing
--
-- Why. enrich_course_text_record_v1 holds a provider's reading as 'held_first_admission' when the provider already has enrich.course_description_pending_max
-- items waiting in Layer 4 ("the rest keep their reading ... admitted once the provider's first ones are approved"). The only thing that ever released them was
-- course_description_release_held_v1, which needs the provider to be TRUSTED (enrich.course_description_review_first decisions in a row, all approvals). While
-- review_first is 100000 (every description waits for a person, Platform Admin 3 Nov 2026) no provider is ever trusted, so a held reading never reached a person:
-- live 7 Nov 2026, 573 readings (30 providers) were stranded, and the standing gap queue would read the same page and spend OpenRouter again after
-- gaps.recheck_days. This migration closes that gap in the way the text above promises: when a person decides one of the provider's items, the next held
-- readings (same bound page, every check run again, not locked, description still empty) become Layer 4 items for a person, up to the same cap.
-- No AI call is made, no Firecrawl credit is used, and nothing is admitted without a decision.

do $guard$
declare v_def text;
begin
  select pg_get_functiondef('security.course_description_review_trg_v1()'::regprocedure) into v_def;
  if md5(v_def) <> 'd143eba24f5896f36a3a93e8e5c075aa' and v_def not like '%course_description_promote_held_v1%' then
    raise exception 'security.course_description_review_trg_v1 is not the definition this migration replaces (md5 %)', md5(v_def);
  end if;
end $guard$;

-- 1. the switch: a setting (G2); on, because it only restores the documented behaviour inside the existing cap
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
('pipeline', 'enrich.course_description_promote_held_on', 'Course description: held readings follow a decision',
 'When a person decides one of a provider''s course descriptions in Layer 4, the provider''s held readings (held_first_admission) take the freed places in the queue, up to enrich.course_description_pending_max. Each is checked again against its stored page first. Nothing is admitted without a person; no AI call is made. 0 = off: held readings wait as before.',
 'number', '1'::jsonb, 0, 1, 'on/off', 1112, 'Course description and deadline', 'security.course_description_promote_held_v1; security.course_description_review_trg_v1',
 'CF-247 course descriptions 7 Nov 2026: held readings were stranded while every description waits for a person')
on conflict (toolset_key, key) do nothing;

-- 2. the promotion
create or replace function security.course_description_promote_held_v1(p_provider uuid) returns integer language plpgsql security definer set search_path = '' as $function$
declare r record; v_n int := 0; v_slots int; v_chk jsonb; v_review uuid; v_text text;
begin
  if p_provider is null or security.pipeline_num_v1('enrich.course_description_promote_held_on', 1) < 1 then return 0; end if;
  -- a trusted provider's held readings are admitted by course_description_release_held_v1, not queued
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
    -- every check runs again on the stored reading (another course may have taken the same words since)
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
comment on function security.course_description_promote_held_v1(uuid) is 'CF-247 (7 Nov 2026): after a person decides one of a provider''s course descriptions in Layer 4, the provider''s held_first_admission readings (same bound page, every check run again, not locked, description empty) take the freed places in the queue, up to enrich.course_description_pending_max. Queues for a person only: no admission, no AI call.';
revoke all on function security.course_description_promote_held_v1(uuid) from public, anon, authenticated;

-- 3. the decision trigger: the same two steps as before, then the promotion (after ANY decision: a rejection frees a place too)
create or replace function security.course_description_review_trg_v1() returns trigger language plpgsql security definer set search_path = '' as $function$
declare v_item bigint := case when coalesce(new.proposed_value->>'item_id', '') ~ '^\d+$' then (new.proposed_value->>'item_id')::bigint end; v_pid uuid;
begin
  if v_item is not null then
    update pipeline.field_enrich_items set state = case when new.status in ('approved', 'edited_approved') then 'filled' else 'skipped' end,
           reason = case when new.status in ('approved', 'edited_approved') then null else 'not admitted in Layer 4 (' || new.status || ')' end, updated_at = now()
     where id = v_item and state = 'review';
  end if;
  select c.provider_id into v_pid from catalogue.courses c where c.id = new.entity_id;
  if new.status in ('approved', 'edited_approved') then
    perform security.course_description_release_held_v1(v_pid);
    insert into search.refresh_requests(requested_by) select 'AI reader (course description, deadline)'
     where not exists (select 1 from search.refresh_requests q where q.processed_at is null and q.requested_by = 'AI reader (course description, deadline)');
  end if;
  perform security.course_description_promote_held_v1(v_pid);
  return null;
end $function$;
comment on function security.course_description_review_trg_v1() is 'CF-247 Workstream C (3 Nov 2026): trigger layer4_review_items_course_description: a decided course description settles its Enrich fields item (filled, or skipped with the decision); an approval admits the provider''s held descriptions once it is trusted; any decision lets the provider''s held readings take the freed place in the queue (7 Nov 2026).';
revoke all on function security.course_description_review_trg_v1() from public, anon, authenticated;

-- 4. housekeeping: the register
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.course_description_promote_held_v1', 'Layer 4', 'Held first-admission course descriptions take the places a decision frees in the provider''s Layer 4 queue (queues for a person; admits nothing)', 'active', '{}', '20261107120000')
on conflict do nothing;
update pipeline.component_register set note = coalesce(note || '. ', '') || '7 Nov 2026 (20261107120000): calls the promotion after any decision', updated_at = now()
 where kind = 'function' and name = 'security.course_description_review_trg_v1' and coalesce(note, '') not like '%20261107120000%';

-- 5. post-check: it ships on, inside the existing cap, and the trust rule is untouched
do $post$ begin
  if security.pipeline_num_v1('enrich.course_description_promote_held_on', 99) not in (0, 1) then raise exception 'post-check: the switch is missing'; end if;
  if security.pipeline_num_v1('enrich.course_description_review_first', 0) < 1 then raise exception 'post-check: review_first must be untouched'; end if;
  if pg_get_functiondef('security.course_description_review_trg_v1()'::regprocedure) not like '%course_description_promote_held_v1%' then raise exception 'post-check: the trigger does not call the promotion'; end if;
end $post$;
