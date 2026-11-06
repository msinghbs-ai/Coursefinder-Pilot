-- Guards: Provider Description mandate production trigger parity, captured 4 Nov 2026.
set check_function_bodies=off;
CREATE OR REPLACE FUNCTION security.manual_field_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_new jsonb; v_old jsonb; f text; v_entity text := case TG_TABLE_NAME when 'courses' then 'course' else 'provider' end;
begin
  if coalesce(current_setting('cf.manual_edit', true), '') = 'on' then return NEW; end if;
  if not exists (select 1 from pipeline.manual_locks l where l.entity = v_entity and l.entity_id = OLD.id) then return NEW; end if;
  v_new := to_jsonb(NEW); v_old := to_jsonb(OLD);
  for f in select l.field from pipeline.manual_locks l where l.entity = v_entity and l.entity_id = OLD.id loop
    if v_old ? f then v_new := jsonb_set(v_new, array[f], v_old->f); end if;
  end loop;
  NEW := jsonb_populate_record(NEW, v_new);
  return NEW;
end $function$
;
CREATE OR REPLACE FUNCTION security.provider_publish_by_default()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.lifecycle_status = 'active' then new.publication_status := 'published'; end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION security.provider_site_followups_tg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if nullif(btrim(NEW.website), '') is null then
    if TG_OP = 'INSERT' then
      insert into pipeline.coverage_provider_discovery(provider_id, status, requested_at, updated_at) values (NEW.id, 'no_website', now(), now())
      on conflict (provider_id) do nothing;
    end if;
  elsif TG_OP = 'INSERT' or nullif(btrim(OLD.website), '') is distinct from nullif(btrim(NEW.website), '') then
    insert into pipeline.provider_central_search(provider_id, state, requested_at) values (NEW.id, 'queued', now())
    on conflict (provider_id) do update set state = 'queued', requested_at = now(), leased_until = null, updated_at = now() where pipeline.provider_central_search.state <> 'leased';
  end if;
  return null;
end $function$
;
CREATE OR REPLACE FUNCTION security.provider_onboarding_new_tg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.lifecycle_status = 'active' and coalesce((select s.auto_start_new from pipeline.provider_onboarding_settings s where s.id = 1), false) then
    insert into pipeline.provider_onboarding(provider_id, source, reason, priority) values (new.id, 'new_provider', 'Added to the catalogue', 100)
    on conflict do nothing;
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION pipeline.layer2_evidence_version_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare v_job_version uuid;
begin
  if new.job_id is not null then
    select source_profile_version_id into v_job_version from pipeline.jobs where id=new.job_id;
    if v_job_version is not null then
      if new.source_profile_version_id is null then new.source_profile_version_id:=v_job_version;
      elsif new.source_profile_version_id<>v_job_version then raise exception 'Evidence configuration version does not match Job configuration version' using errcode='23514';
      end if;
    end if;
  end if;
  return new;
end
$function$
;
CREATE OR REPLACE FUNCTION security.layer2_evidence_lineage_stamp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v_lineage jsonb;
begin
  if new.job_id is null then return new; end if;
  v_lineage:=security.layer2_lineage_for_job(new.job_id);
  if v_lineage is not null then
    new.metadata:=coalesce(new.metadata,'{}'::jsonb)||jsonb_build_object('layer2_lineage',v_lineage);
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION security.course_description_review_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_item bigint := case when coalesce(new.proposed_value->>'item_id', '') ~ '^\d+$' then (new.proposed_value->>'item_id')::bigint end; v_pid uuid;
begin
  if v_item is not null then
    update pipeline.field_enrich_items set state = case when new.status in ('approved', 'edited_approved') then 'filled' else 'skipped' end,
           reason = case when new.status in ('approved', 'edited_approved') then null else 'not admitted in Layer 4 (' || new.status || ')' end, updated_at = now()
     where id = v_item and state = 'review';
  end if;
  if new.status in ('approved', 'edited_approved') then
    select c.provider_id into v_pid from catalogue.courses c where c.id = new.entity_id;
    perform security.course_description_release_held_v1(v_pid);
    insert into search.refresh_requests(requested_by) select 'AI reader (course description, deadline)'
     where not exists (select 1 from search.refresh_requests q where q.processed_at is null and q.requested_by = 'AI reader (course description, deadline)');
  end if;
  return null;
end $function$
;
CREATE OR REPLACE FUNCTION security.course_entry_review_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.status in ('rejected', 'more_evidence', 'returned_layer2', 'returned_layer3', 'superseded') then
    perform security.course_entry_review_apply_v1(new.id, new.status, null, 'Layer 4 ' || new.status);
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION security.entry_matrix_review_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.status in ('rejected', 'more_evidence', 'returned_layer2', 'returned_layer3', 'superseded') then
    perform security.entry_matrix_review_apply_v1(new.id, new.status, null, 'Layer 4 ' || new.status);
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION security.no_page_review_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.status in ('rejected', 'more_evidence', 'returned_layer2', 'returned_layer3', 'superseded') then
    perform security.no_page_review_apply_v1(new.id, new.status, null, 'Layer 4 ' || new.status);
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION security.provider_description_review_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update pipeline.provider_description_reads set
         state = case when new.status = 'rejected' then 'rejected' when new.status in ('more_evidence', 'returned_layer2', 'returned_layer3') then 'held' when new.status = 'superseded' then 'superseded' else state end,
         rule = case when new.status in ('approved', 'edited_approved') then rule else 'layer4_' || new.status end,
         updated_at = now()
   where review_item_id = new.id and state = 'proposed' and new.status not in ('approved', 'edited_approved');
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION security.layer4_reroute_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.entity_type = 'course' and new.status = 'pending' and security.layer4_reroute_course_v1(new.entity_id, new.field_code, true) then
    new.status := 'superseded'; new.decided_at := now();
    new.change_control_ref := coalesce(new.change_control_ref || '; ', '') || 'CF-247 v2.15.250: rerouted to the university adapter';
    insert into pipeline.layer4_reroutes(item_id, entity_type, entity_id, field_code, route, note) values (new.id, 'course', new.entity_id, new.field_code, 'adapter', 'on arrival');
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION security.layer4_arrival_guard_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- Trigger layer4_review_items_zz_arrival (BEFORE INSERT; after layer4_review_items_reroute, before ops_guard_layer4). While layer4.arrival_guard_on
-- is 1, a new waiting item of a kind in layer4.platform_kinds that the platform can settle (security.layer4_resolution_for_v1) arrives superseded,
-- with the reason recorded in pipeline.layer4_supersessions. It never approves, rejects or changes any other row. Every generator passes here.
declare v_res jsonb;
begin
  if new.status is distinct from 'pending' or security.pipeline_num_v1('layer4.arrival_guard_on', 0) < 1
     or not (new.field_code = any (security.pipeline_list_v1('layer4.platform_kinds', '[]'::jsonb))) then
    return new;
  end if;
  new.id := coalesce(new.id, gen_random_uuid());
  v_res := security.layer4_resolution_for_v1(new.id, new.entity_type, new.entity_id, new.field_code, new.proposed_value, new.layer2_state, new.evidence_id, coalesce(new.created_at, now()));
  if v_res is null then return new; end if;
  new.status := 'superseded';
  new.decided_at := now();
  new.change_control_ref := coalesce(new.change_control_ref || '; ', '') || 'CF-247 L4 readiness: settled on arrival (' || (v_res->>'reason') || ')';
  insert into pipeline.layer4_supersessions(item_id, field_code, entity_type, entity_id, reason, covered_by_item, evidence, mode)
  values (new.id, new.field_code, new.entity_type, new.entity_id, v_res->>'reason', nullif(v_res->>'covered_by_item', '')::uuid, coalesce(v_res->'evidence', '{}'::jsonb), 'arrival');
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION security.layer4_evidence_link_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- Trigger layer4_review_items_zz_evidence (BEFORE INSERT): a new waiting item of a kind in layer4.evidence_link_kinds that arrives without a
-- stored copy gets the newest stored copy of its page. No read is made; nothing else changes.
begin
  if new.evidence_id is null and new.status = 'pending' and security.pipeline_num_v1('layer4.evidence_link_on', 1) >= 1
     and new.field_code = any (security.pipeline_list_v1('layer4.evidence_link_kinds', '[]'::jsonb)) then
    new.evidence_id := security.layer4_stored_copy_v1(security.layer4_item_page_v1(new.field_code, new.proposed_value, new.layer2_state));
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION security.ops_guard_layer4_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
-- While a remedy runs a Layer 4 item may only stay pending or be superseded (duplicate reconciliation); approving, rejecting, returning or
-- deleting is a decision (mandate §10: technical repair authority is not admission authority).
begin
  if TG_OP = 'DELETE' or new.status not in ('pending', 'superseded') or (TG_OP = 'UPDATE' and old.status <> 'pending' and new.status is distinct from old.status) then
    raise exception 'ops guard: a remedy cannot decide or admit a Layer 4 item' using errcode = '42501';
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION security.layer4_return_layer3_requeue_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline'
AS $function$
declare v_item pipeline.layer4_review_items%rowtype;
begin
  if new.action<>'return_layer3' then return new; end if;
  select * into v_item from pipeline.layer4_review_items where id=new.review_item_id;
  if v_item.field_code<>'provider_current_tuition_validation' or v_item.layer3_interpretation_id is null then return new; end if;
  update pipeline.layer3_work_items w
  set status='pending', available_at=now(), completed_at=null, reserved_at=null, reserved_by=null,
      last_error='Returned by a Layer 4 reviewer for another AI check',
      corrective_retry_reason=left('Layer 4 send-back: '||coalesce(new.reason,''),2000),
      corrective_retry_count=w.corrective_retry_count + case when w.attempt_count>=5 then 1 else 0 end,
      corrective_retry_authorized_at=case when w.attempt_count>=5 then now() else w.corrective_retry_authorized_at end,
      updated_at=now()
  where w.interpretation_id=v_item.layer3_interpretation_id and w.status in ('layer4_required','parked','no_candidate','rejected');
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION security.ops_guard_refuse_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
-- Fires only while a remedy or verification runs (trigger WHEN security.ops_remedy_guard_active_v1()). TG_ARGV[0] names what is protected.
begin
  raise exception 'ops guard: a remedy cannot change % (%.%; that is a release or a Platform Admin decision)', TG_ARGV[0], TG_TABLE_SCHEMA, TG_TABLE_NAME using errcode = '42501';
end $function$
;
CREATE OR REPLACE FUNCTION security.ai_spend_capture_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- Decision 5 E-7 (2 Nov 2026): records the AI cost a row gains. tg_argv: lane, how ('delta' = the increase of an accumulated cost;
-- 'decision' = the cost of each decision of a leased item, as svc_coverage_ai_match_record overwrites it), the path of the cost in the row.
declare v_new jsonb := to_jsonb(new); v_old jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end; v_path text[] := tg_argv[2]::text[];
        v_add numeric;
begin
  if tg_argv[1] = 'decision' then
    if tg_op = 'UPDATE' and not (v_old->>'state' = 'leased' and v_new->>'state' <> 'leased'
                                 and (v_new->>'decided_at') is distinct from (v_old->>'decided_at')) then return null; end if;
    v_add := coalesce((v_new #>> v_path)::numeric, 0);
  else
    v_add := coalesce((v_new #>> v_path)::numeric, 0) - coalesce((v_old #>> v_path)::numeric, 0);
  end if;
  if v_add > 0 then
    insert into pipeline.ai_spend_ledger(lane, source, source_id, cost_usd) values (tg_argv[0], tg_table_name, v_new->>'id', v_add);
  end if;
  return null;
end $function$
;
drop trigger if exists manual_lock_guard on catalogue.providers;
CREATE TRIGGER manual_lock_guard BEFORE UPDATE ON catalogue.providers FOR EACH ROW EXECUTE FUNCTION security.manual_field_guard();
drop trigger if exists provider_publish_by_default on catalogue.providers;
CREATE TRIGGER provider_publish_by_default BEFORE INSERT ON catalogue.providers FOR EACH ROW EXECUTE FUNCTION security.provider_publish_by_default();
drop trigger if exists provider_site_followups on catalogue.providers;
CREATE TRIGGER provider_site_followups AFTER INSERT OR UPDATE OF website ON catalogue.providers FOR EACH ROW EXECUTE FUNCTION security.provider_site_followups_tg();
drop trigger if exists providers_onboarding_new on catalogue.providers;
CREATE TRIGGER providers_onboarding_new AFTER INSERT ON catalogue.providers FOR EACH ROW EXECUTE FUNCTION security.provider_onboarding_new_tg();
drop trigger if exists layer2_evidence_version_guard on pipeline.evidence_artifacts;
CREATE TRIGGER layer2_evidence_version_guard BEFORE INSERT OR UPDATE OF job_id, source_profile_version_id ON pipeline.evidence_artifacts FOR EACH ROW EXECUTE FUNCTION pipeline.layer2_evidence_version_guard();
drop trigger if exists trg_layer2_evidence_lineage_stamp on pipeline.evidence_artifacts;
CREATE TRIGGER trg_layer2_evidence_lineage_stamp BEFORE INSERT ON pipeline.evidence_artifacts FOR EACH ROW EXECUTE FUNCTION security.layer2_evidence_lineage_stamp();
drop trigger if exists layer4_review_items_course_description on pipeline.layer4_review_items;
CREATE TRIGGER layer4_review_items_course_description AFTER UPDATE OF status ON pipeline.layer4_review_items FOR EACH ROW WHEN (old.status = 'pending'::text AND new.status <> 'pending'::text AND new.field_code = 'course_description_first_read'::text) EXECUTE FUNCTION security.course_description_review_trg_v1();
drop trigger if exists layer4_review_items_course_entry on pipeline.layer4_review_items;
CREATE TRIGGER layer4_review_items_course_entry AFTER UPDATE OF status ON pipeline.layer4_review_items FOR EACH ROW WHEN (old.status = 'pending'::text AND new.status <> 'pending'::text AND new.field_code = 'course_entry_first_read'::text) EXECUTE FUNCTION security.course_entry_review_trg_v1();
drop trigger if exists layer4_review_items_entry_matrix on pipeline.layer4_review_items;
CREATE TRIGGER layer4_review_items_entry_matrix AFTER UPDATE OF status ON pipeline.layer4_review_items FOR EACH ROW WHEN (old.status = 'pending'::text AND new.status <> 'pending'::text AND (new.field_code = ANY (ARRAY['entry_matrix_first_run'::text, 'entry_matrix_change'::text]))) EXECUTE FUNCTION security.entry_matrix_review_trg_v1();
drop trigger if exists layer4_review_items_no_page on pipeline.layer4_review_items;
CREATE TRIGGER layer4_review_items_no_page AFTER UPDATE OF status ON pipeline.layer4_review_items FOR EACH ROW WHEN (old.status = 'pending'::text AND new.status <> 'pending'::text AND (new.field_code = ANY (ARRAY['no_page_first_run'::text, 'conjoint_rule_first_run'::text]))) EXECUTE FUNCTION security.no_page_review_trg_v1();
drop trigger if exists layer4_review_items_provider_description on pipeline.layer4_review_items;
CREATE TRIGGER layer4_review_items_provider_description AFTER UPDATE OF status ON pipeline.layer4_review_items FOR EACH ROW WHEN (old.status = 'pending'::text AND new.status <> 'pending'::text AND new.field_code = 'provider_description'::text) EXECUTE FUNCTION security.provider_description_review_trg_v1();
drop trigger if exists layer4_review_items_reroute on pipeline.layer4_review_items;
CREATE TRIGGER layer4_review_items_reroute BEFORE INSERT ON pipeline.layer4_review_items FOR EACH ROW EXECUTE FUNCTION security.layer4_reroute_trg_v1();
drop trigger if exists layer4_review_items_zz_arrival on pipeline.layer4_review_items;
CREATE TRIGGER layer4_review_items_zz_arrival BEFORE INSERT ON pipeline.layer4_review_items FOR EACH ROW EXECUTE FUNCTION security.layer4_arrival_guard_trg_v1();
drop trigger if exists layer4_review_items_zz_evidence on pipeline.layer4_review_items;
CREATE TRIGGER layer4_review_items_zz_evidence BEFORE INSERT ON pipeline.layer4_review_items FOR EACH ROW EXECUTE FUNCTION security.layer4_evidence_link_trg_v1();
drop trigger if exists ops_guard_layer4 on pipeline.layer4_review_items;
CREATE TRIGGER ops_guard_layer4 BEFORE INSERT OR DELETE OR UPDATE ON pipeline.layer4_review_items FOR EACH ROW WHEN (security.ops_remedy_guard_active_v1()) EXECUTE FUNCTION security.ops_guard_layer4_v1();
drop trigger if exists layer4_return_layer3_requeue on pipeline.layer4_decisions;
CREATE TRIGGER layer4_return_layer3_requeue AFTER INSERT ON pipeline.layer4_decisions FOR EACH ROW EXECUTE FUNCTION security.layer4_return_layer3_requeue_trg();
drop trigger if exists ops_guard_layer4 on pipeline.layer4_decisions;
CREATE TRIGGER ops_guard_layer4 BEFORE INSERT OR DELETE OR UPDATE ON pipeline.layer4_decisions FOR EACH ROW WHEN (security.ops_remedy_guard_active_v1()) EXECUTE FUNCTION security.ops_guard_refuse_v1('Layer 4 decisions');
drop trigger if exists ai_spend_capture on pipeline.provider_description_reads;
CREATE TRIGGER ai_spend_capture AFTER INSERT OR UPDATE OF cost_usd ON pipeline.provider_description_reads FOR EACH ROW EXECUTE FUNCTION security.ai_spend_capture_v1('provider_description', 'delta', '{cost_usd}');
