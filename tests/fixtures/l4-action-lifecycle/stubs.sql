-- CF-247 Layer 4 action lifecycle fixtures: the production columns the lifecycle reads that the earlier fixture stubs left out (live
-- information_schema read 4 Nov 2026 12:29-12:30 AEDT). Nothing else changes.
alter table pipeline.admin_control_events add column if not exists created_at timestamptz not null default now();
alter table pipeline.aer_read_supersessions add column if not exists closed_at timestamptz;
alter table pipeline.field_enrich_items add column if not exists evidence_id uuid, add column if not exists reason text,
  add column if not exists created_at timestamptz not null default now(), add column if not exists attempts int not null default 0, add column if not exists source text;
alter table pipeline.enrichment_flags add column if not exists released_at timestamptz, add column if not exists next_check_at timestamptz,
  add column if not exists updated_at timestamptz not null default now(), add column if not exists cleared_at timestamptz;
alter table pipeline.provider_onboarding add column if not exists finished_at timestamptz, add column if not exists attempts int not null default 0;
alter table pipeline.data_flags add column if not exists resolved_at timestamptz, add column if not exists resolution jsonb;
alter table pipeline.layer1_provider_departures add column if not exists reviewed_at timestamptz, add column if not exists reviewed_by uuid;
alter table catalogue.course_entry_requirements add column if not exists source_url text;
-- the live D-R2 close (20261103070000): a row moves once from requested to superseded or refused, with its time
create or replace function security.aer_read_supersession_close_v1(p_id uuid, p_state text, p_why text, p_new_item uuid, p_diff jsonb) returns void
language sql security definer set search_path to '' as $f$
  update pipeline.aer_read_supersessions set state = p_state, outcome = left(p_why, 500), new_item_id = p_new_item, closed_at = now() where id = p_id and state = 'requested'
$f$;
-- the live corrected read (20261103070000, live md5 1e2947b3) answers {job_id, request_id, enrich_item_id, review_item_id} and reads the course's
-- bound page from its stored copy; the stand-in keeps that shape (the reader itself is fx.reader below)
create or replace function security.course_entry_correction_v1(p_item uuid, p_actor uuid, p_reason text) returns jsonb language plpgsql as $f$
declare o pipeline.layer4_review_items; v_e bigint; v_s uuid; v_j uuid := gen_random_uuid();
begin
  select * into o from pipeline.layer4_review_items where id = p_item;
  if exists (select 1 from pipeline.aer_read_supersessions s where s.old_item_id = p_item and s.state = 'requested') then
    raise exception 'No corrected read (D-R2): a corrected read of this item is already asked for. Nothing was changed'; end if;
  insert into pipeline.field_enrich_items(course_id, field, state, job_id, evidence_id, source)
  values (o.entity_id, 'entry_requirements', 'queued', v_j, (select g.evidence_id from pipeline.coverage_course_pages g where g.course_id = o.entity_id), 'ai_stored') returning id into v_e;
  insert into pipeline.aer_read_supersessions(old_item_id, course_id, source_url, old_evidence_id, enrich_item_id, job_id, requested_by, reason)
  values (p_item, o.entity_id, coalesce((select g.url from pipeline.coverage_course_pages g where g.course_id = o.entity_id), 'https://x'), o.evidence_id, v_e, v_j, p_actor, p_reason)
  returning id into v_s;
  return jsonb_build_object('job_id', v_j, 'request_id', v_s, 'enrich_item_id', v_e, 'review_item_id', p_item);
end $f$;
-- the reader's outcome for a requested corrected read, as security.enrich_entry_record_v1 records it (refused: held, nothing proposed;
-- superseded: a new pending item replaces the old one, which becomes 'superseded')
create or replace function fx.reader(p_enrich bigint, p_state text, p_why text) returns uuid language plpgsql as $f$
declare s pipeline.aer_read_supersessions; v_new uuid;
begin
  select * into s from pipeline.aer_read_supersessions where enrich_item_id = p_enrich;
  if p_state = 'superseded' then
    update pipeline.layer4_review_items set status = 'superseded', decided_at = now() where id = s.old_item_id;
    insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status, escalation_reason, evidence_id)
    values ('course', s.course_id, 'course_entry_first_read', 'pending', 'Course entry requirements first read', (select f.evidence_id from pipeline.field_enrich_items f where f.id = p_enrich))
    returning id into v_new;
    update pipeline.field_enrich_items set state = 'review', updated_at = now() where id = p_enrich;
  else
    update pipeline.field_enrich_items set state = 'skipped', reason = 'held_partial: ' || p_why, updated_at = now() where id = p_enrich;
  end if;
  perform security.aer_read_supersession_close_v1(s.id, p_state, p_why, v_new, null);
  return v_new;
end $f$;
-- live pipeline.data_flags.id is a uuid (the earlier stub made it bigserial; the table is empty here)
alter table pipeline.data_flags alter column id drop default;
alter table pipeline.data_flags alter column id type uuid using gen_random_uuid();
alter table pipeline.data_flags alter column id set default gen_random_uuid();
