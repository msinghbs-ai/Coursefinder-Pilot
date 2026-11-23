-- CF-247 s1023 (S1-Build; Platform Admin 24 Nov 2026 05:51 and 08:22 AEDT; UI-UX plan v1.2 slice 5): shadow audit of locked fees and intakes, and
-- Approve & Keep Lock. A machine write to a field a person has locked is dropped by security.manual_fact_guard (unchanged) and so far was dropped
-- silently. Now, for tuition (catalogue.course_fees, provider_current_tuition) and intakes (catalogue.course_intakes), a dropped write whose value
-- differs from the live value opens one Layer 4 item "Periodic Audit - Locked Field Update" (Inbox kind locked_field_update): live value,
-- proposed value, source and stored copy, and the lock (who set it, when). One open item per course, field and proposed value; a re-read of the
-- same value only counts again. The sweeps are not changed and gain no job: the check sits where every machine write to a locked field already
-- arrives (the guard on the table).
-- Decisions (rank 3 and up; a reason is required): Approve & Keep Lock writes the proposed value as a person's edit (cf.manual_edit) and leaves the
-- lock row exactly as it is; Reject closes the item and changes nothing. Bulk: security.layer4_locked_update_bulk_v1 through
-- public.admin_layer4_locked_update_bulk (same reason for every selected item, at most layer4.locked_update_bulk_max). Each decision is logged in
-- pipeline.admin_control_events. The Layer 4 card and bulk bar are S1-API-Frontend-Delivery's (master plan hand-off).
-- Live before this change (rolled back, 24 Nov 2026): 7,585 locks; 2 tuition locks, intake locks on 15 courses; security.manual_fact_guard md5
-- d0490f37 (the edit is md5-guarded; only the locked branch gains the audit call, which can never fail the write path).
-- G1: no job. G2: the audit switch and the bulk limit are settings. G3: no consumer object changed (checked); locked values change only by a
-- person's decision. Manual locks and active cron checked unchanged. Nothing dropped or deleted.
-- Replaces: the silent drop of a machine write to a locked tuition or intake field.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads and the function change

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(replace(pg_get_functiondef('security.manual_fact_guard'::regproc), chr(13), '')) <> 'd0490f3707199988e87b5f37ca5e7342' then
    raise exception 'guard: security.manual_fact_guard is not the definition this change was written against';
  end if;
end $g$;
create temp table s1023_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1023_cron on commit drop as select count(*) n from cron.job where active;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'layer4.locked_update_audit_on', 'Locked fields: open a review when a re-read differs',
        'On (1): when a fee or intake sweep reads a value for a field a person has locked and it differs from the live value, the value is not written (the lock holds) and a Periodic Audit - Locked Field Update item opens in Layer 4. Off (0): the read is dropped silently, as before.',
        'number', to_jsonb(1), 0, 1, 'on/off', 1215, 'Layer 4 review', 'security.locked_field_update_raise_v1 (from security.manual_fact_guard)', 'CF-247 s1023: UI-UX plan v1.2 slice 5 (Platform Admin 24 Nov 2026)'),
       ('pipeline', 'layer4.locked_update_bulk_max', 'Locked fields: most items in one bulk decision',
        'How many Locked Field Update items one Approve & Keep Lock or Reject in bulk may decide at once. Every item gets the same reason.',
        'number', to_jsonb(100), 1, 500, 'items', 1216, 'Layer 4 review', 'security.layer4_locked_update_bulk_v1', 'CF-247 s1023: UI-UX plan v1.2 slice 5 (Platform Admin 24 Nov 2026)')
on conflict do nothing;

create table if not exists pipeline.locked_field_updates (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null,
  provider_id uuid,
  field text not null check (field in ('tuition', 'intakes')),
  op text not null,
  target_id uuid,
  proposed jsonb not null,
  proposed_key text not null,
  live jsonb not null default '[]'::jsonb,
  lock_set_by uuid,
  lock_set_at timestamptz,
  source_id uuid,
  evidence_id uuid,
  status text not null default 'open',
  opened_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  seen_count int not null default 1,
  decision text,
  reason text,
  decided_by uuid,
  decided_at timestamptz,
  applied_id uuid
);
comment on table pipeline.locked_field_updates is 'CF-247 s1023: machine re-reads of locked tuition and intake fields that differ from the live value, held for a person (Layer 4 kind locked_field_update, Approve & Keep Lock).';
create unique index if not exists locked_field_updates_open_uq on pipeline.locked_field_updates (course_id, field, proposed_key) where status = 'open';
create index if not exists locked_field_updates_open_idx on pipeline.locked_field_updates (provider_id, opened_at) where status = 'open';
alter table pipeline.locked_field_updates enable row level security;
revoke all on pipeline.locked_field_updates from public, anon, authenticated;

-- The values compared: what a counsellor sees for the field.
CREATE OR REPLACE FUNCTION security.locked_field_value_v1(p_field text, p_row jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case p_field
    when 'tuition' then jsonb_build_object('fee_year', p_row->'fee_year', 'audience', p_row->'audience', 'amount', p_row->'amount', 'currency_code', p_row->'currency_code',
                                           'basis', p_row->'basis', 'load_basis', p_row->'load_basis', 'campus_id', p_row->'campus_id')
    when 'intakes' then jsonb_build_object('intake_year', p_row->'intake_year', 'intake_label', p_row->'intake_label', 'start_date', p_row->'start_date',
                                           'application_deadline', p_row->'application_deadline', 'campus_id', p_row->'campus_id') end
$function$;

CREATE OR REPLACE FUNCTION security.locked_field_update_raise_v1(p_field text, p_new jsonb, p_old jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_course uuid := (p_new->>'course_id')::uuid; v_val jsonb := security.locked_field_value_v1(p_field, p_new); v_live jsonb; v_key text; v_id uuid; l record;
begin
  if security.pipeline_num_v1('layer4.locked_update_audit_on', 1) < 1 or v_course is null then return null; end if;
  if p_field = 'tuition' then
    if coalesce(p_new->>'status', 'active') <> 'active' then return null; end if;
    select coalesce(jsonb_agg(security.locked_field_value_v1('tuition', to_jsonb(f)) order by f.fee_year desc), '[]'::jsonb) into v_live
      from catalogue.course_fees f where f.course_id = v_course and f.fee_type = 'provider_current_tuition' and f.status = 'active';
  else
    if coalesce(p_new->>'status', 'active') <> 'active' then return null; end if;
    select coalesce(jsonb_agg(security.locked_field_value_v1('intakes', to_jsonb(i)) order by i.start_date nulls last), '[]'::jsonb) into v_live
      from catalogue.course_intakes i where i.course_id = v_course and i.status = 'active';
  end if;
  if v_live @> jsonb_build_array(v_val) then return null; end if;  -- the live value already says this: nothing to review
  v_key := md5(v_val::text);
  select * into l from pipeline.manual_locks m where m.entity = 'course' and m.entity_id = v_course and m.field = p_field limit 1;
  insert into pipeline.locked_field_updates(course_id, provider_id, field, op, target_id, proposed, proposed_key, live, lock_set_by, lock_set_at, source_id, evidence_id)
  values (v_course, (select c.provider_id from catalogue.courses c where c.id = v_course), p_field, case when p_old is null then 'insert' else 'update' end,
          (p_old->>'id')::uuid, p_new - 'id', v_key, v_live, l.set_by, l.set_at, (p_new->>'source_id')::uuid, (p_new->>'evidence_id')::uuid)
  on conflict (course_id, field, proposed_key) where status = 'open'
  do update set last_seen_at = now(), seen_count = pipeline.locked_field_updates.seen_count + 1, live = excluded.live,
                evidence_id = coalesce(excluded.evidence_id, pipeline.locked_field_updates.evidence_id), source_id = coalesce(excluded.source_id, pipeline.locked_field_updates.source_id)
  returning id into v_id;
  return v_id;
end $function$;
revoke all on function security.locked_field_update_raise_v1(text, jsonb, jsonb) from public, anon, authenticated;

-- The guard: unchanged except that the locked branch records the dropped value for tuition and intakes first (never failing the write path).
CREATE OR REPLACE FUNCTION security.manual_fact_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r jsonb; v_field text;
begin
  if coalesce(current_setting('cf.manual_edit', true), '') = 'on' then
    if TG_OP = 'DELETE' then return OLD; end if;
    return NEW;
  end if;
  if TG_OP = 'DELETE' then r := to_jsonb(OLD); else r := to_jsonb(NEW); end if;
  v_field := case TG_TABLE_NAME
    when 'course_links' then case when r->>'link_type' = 'official_course' then 'official_url' else 'link:' || (r->>'link_type') end
    when 'course_intakes' then 'intakes'
    when 'course_english_requirements' then 'english'
    when 'course_fees' then case when r->>'fee_type' = 'provider_current_tuition' then 'tuition' end
  end;
  if v_field is not null and exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = (r->>'course_id')::uuid and l.field = v_field) then
    if TG_OP <> 'DELETE' and v_field in ('tuition', 'intakes') then
      begin  -- CF-247 s1023: shadow audit of a locked field; the lock still holds
        perform security.locked_field_update_raise_v1(v_field, r, case when TG_OP = 'UPDATE' then to_jsonb(OLD) end);
      exception when others then
        raise warning 'locked field audit not recorded for course %: %', r->>'course_id', sqlerrm;
      end;
    end if;
    return null;
  end if;
  if TG_OP = 'DELETE' then return OLD; end if;
  return NEW;
end $function$;

-- Layer 4 Inbox kind
CREATE OR REPLACE FUNCTION security.layer4_locked_update_kind_v1()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select '{"label": "Periodic Audit - Locked Field Update", "order": 36, "choices": [
     {"key": "approve_keep_lock", "label": "Yes (Approve & Keep Lock)", "rank": 3, "reason": true, "returns": "The live value becomes the value read from the source; the manual lock stays as it is"},
     {"key": "reject", "label": "No (keep the live value)", "rank": 3, "reason": true, "returns": "The live value and the lock stay as they are; the item closes"}]}'::jsonb
$function$;

CREATE OR REPLACE FUNCTION security.layer4_locked_update_inbox_counts_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with o as (select * from pipeline.locked_field_updates where status = 'open')
  select jsonb_build_object('kind', 'locked_field_update', 'n', (select count(*) from o), 'oldest', (select min(o.opened_at) from o),
    'late', (select count(*) from o where o.opened_at < now() - make_interval(days => security.pipeline_num_v1('layer4.target_days', 7)::int)),
    'by_provider', coalesce((select jsonb_agg(jsonb_build_object('provider_id', z.provider_id, 'n', z.n, 'oldest', z.oldest) order by z.oldest)
                               from (select o.provider_id, count(*) n, min(o.opened_at) oldest from o group by 1) z), '[]'::jsonb))
$function$;

CREATE OR REPLACE FUNCTION security.layer4_locked_update_inbox_page_v1(p_args jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with o as (select r.* from pipeline.locked_field_updates r
              where r.status = 'open' and (nullif(p_args->>'provider_id', '') is null or r.provider_id = (p_args->>'provider_id')::uuid)),
  x as (select o.* from o
         where nullif(p_args->>'after_ref', '') is null or (o.opened_at, o.id::text) > ((p_args->>'after_at')::timestamptz, p_args->>'after_ref')
         order by o.opened_at, o.id::text
         limit least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200))  -- fixed: page size bounds, as the Inbox's own
  select jsonb_build_object('kind', 'locked_field_update',
    'before', case when nullif(p_args->>'after_ref', '') is not null then
                (select count(*) from o where (o.opened_at, o.id::text) <= ((p_args->>'after_at')::timestamptz, p_args->>'after_ref')) end,
    'items', coalesce((select jsonb_agg(jsonb_build_object('kind', 'locked_field_update', 'ref', x.id::text, 'provider_id', x.provider_id,
           'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = x.provider_id),
           'subject', coalesce((select coalesce(c.display_title, c.canonical_title) from catalogue.courses c where c.id = x.course_id), 'Course') || ' · ' ||
                      case x.field when 'tuition' then 'Tuition ' || coalesce(x.proposed->>'fee_year', '?') || ' ' || coalesce(x.proposed->>'currency_code', '') || ' ' || coalesce(x.proposed->>'amount', '?')
                                   else 'Intake ' || coalesce(x.proposed->>'start_date', x.proposed->>'intake_label', '?') end,
           'why', 'A re-read differs from the value a person locked', 'suggestion', 'Compare with the source; approve to update the value and keep the lock',
           'field', x.field, 'seen_count', x.seen_count, 'created_at', x.opened_at,
           'late', x.opened_at < now() - make_interval(days => security.pipeline_num_v1('layer4.target_days', 7)::int)) order by x.opened_at, x.id::text) from x), '[]'::jsonb))
$function$;

CREATE OR REPLACE FUNCTION security.layer4_locked_update_inbox_detail_v1(p_ref text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'sections', jsonb_build_array(
      jsonb_build_object('key', 'proposed', 'title', 'Value read from the source', 'body', security.locked_field_value_v1(r.field, r.proposed)),
      jsonb_build_object('key', 'live', 'title', 'Live value (locked)', 'body', jsonb_build_object('Live rows', r.live)),
      jsonb_build_object('key', 'source', 'title', 'Source and stored copy', 'body', jsonb_build_object('Source', r.source_id, 'Stored copy (evidence)', r.evidence_id,
                         'Source page', (select e.metadata->>'source_url' from pipeline.evidence_artifacts e where e.id = r.evidence_id), 'Read', r.seen_count || ' time(s), last ' || to_char(r.last_seen_at at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI'))),
      jsonb_build_object('key', 'lock', 'title', 'The lock', 'body', jsonb_build_object('Field', r.field, 'Set by', r.lock_set_by, 'Set at', r.lock_set_at)),
      jsonb_build_object('key', 'rule', 'title', 'The rule',
        'body', 'A locked value changes only by a person''s decision. Approve & Keep Lock writes the value read from the source and keeps the lock; the sweeps keep leaving it alone.')),
    'actions', jsonb_build_array(jsonb_build_object('key', 'approve_keep_lock', 'allowed', true), jsonb_build_object('key', 'reject', 'allowed', true)))
    from pipeline.locked_field_updates r
   where r.id::text = p_ref and r.status = 'open'
$function$;

CREATE OR REPLACE FUNCTION security.layer4_locked_update_inbox_decide_v1(p_ref text, p_choice text, p_value text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r pipeline.locked_field_updates; v_ev bigint; v_applied uuid; v_n int := 0; v_locks0 bigint; v_returns text;
        v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if p_choice not in ('approve_keep_lock', 'reject') then raise exception 'unknown choice %', p_choice using errcode = '22023'; end if;
  if v_reason is null then
    return jsonb_build_object('ok', false, 'kind', 'locked_field_update', 'choice', p_choice, 'ref', p_ref, 'request', 'Give the reason for this decision; it is kept in the audit log.');
  end if;
  select * into r from pipeline.locked_field_updates where id::text = p_ref and status = 'open' for update;
  if not found then
    return jsonb_build_object('ok', false, 'kind', 'locked_field_update', 'choice', p_choice, 'ref', p_ref, 'request', 'This item has already been decided; refresh the Inbox.');
  end if;
  select count(*) into v_locks0 from pipeline.manual_locks;
  if p_choice = 'approve_keep_lock' then
    perform set_config('cf.manual_edit', 'on', true);
    if r.field = 'tuition' then
      if r.op = 'update' and r.target_id is not null and exists (select 1 from catalogue.course_fees f where f.id = r.target_id) then
        update catalogue.course_fees f set fee_year = (r.proposed->>'fee_year')::int, audience = r.proposed->>'audience', amount = (r.proposed->>'amount')::numeric,
               currency_code = r.proposed->>'currency_code', basis = r.proposed->>'basis', load_basis = r.proposed->>'load_basis', campus_id = (r.proposed->>'campus_id')::uuid,
               source_id = coalesce((r.proposed->>'source_id')::uuid, f.source_id), evidence_id = coalesce((r.proposed->>'evidence_id')::uuid, f.evidence_id), status = 'active'
         where f.id = r.target_id returning f.id into v_applied;
      else
        -- the value read replaces the live fee for the same audience and year (a fee change); another year is a new row and the
        -- one-current rule (security.course_fee_one_current_trg) settles which year is current
        update catalogue.course_fees f set status = 'superseded'
         where f.course_id = r.course_id and f.fee_type = 'provider_current_tuition' and f.status = 'active'
           and f.audience is not distinct from r.proposed->>'audience' and f.fee_year is not distinct from (r.proposed->>'fee_year')::int;
        insert into catalogue.course_fees select * from jsonb_populate_record(null::catalogue.course_fees, r.proposed || jsonb_build_object('id', gen_random_uuid(), 'status', 'active'))
        returning id into v_applied;
      end if;
    else
      if r.op = 'update' and r.target_id is not null and exists (select 1 from catalogue.course_intakes i where i.id = r.target_id) then
        update catalogue.course_intakes i set intake_year = (r.proposed->>'intake_year')::int, intake_label = r.proposed->>'intake_label', start_date = (r.proposed->>'start_date')::date,
               application_deadline = (r.proposed->>'application_deadline')::date, campus_id = (r.proposed->>'campus_id')::uuid,
               source_id = coalesce((r.proposed->>'source_id')::uuid, i.source_id), evidence_id = coalesce((r.proposed->>'evidence_id')::uuid, i.evidence_id), status = 'active'
         where i.id = r.target_id returning i.id into v_applied;
      else
        insert into catalogue.course_intakes select * from jsonb_populate_record(null::catalogue.course_intakes, r.proposed || jsonb_build_object('id', gen_random_uuid(), 'status', 'active'))
        returning id into v_applied;
      end if;
    end if;
    perform set_config('cf.manual_edit', '', true);
    v_returns := 'The live value now matches the source; the manual lock is unchanged.';
  else
    v_returns := 'Nothing changed; the live value and the lock stay as they are.';
  end if;
  if (select count(*) from pipeline.manual_locks) <> v_locks0 then raise exception 'a Locked Field Update decision must not change the manual locks'; end if;
  update pipeline.locked_field_updates set status = case when p_choice = 'approve_keep_lock' then 'approved' else 'rejected' end, decision = p_choice, reason = v_reason,
         decided_by = auth.uid(), decided_at = now(), applied_id = v_applied where id = r.id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', 'locked_field_update:' || p_ref, jsonb_build_object('kind', 'locked_field_update', 'ref', p_ref, 'choice', p_choice, 'reason', v_reason,
          'course_id', r.course_id, 'provider_id', r.provider_id, 'field', r.field, 'proposed', security.locked_field_value_v1(r.field, r.proposed), 'live', r.live,
          'evidence_id', r.evidence_id, 'applied_id', v_applied, 'lock_kept', true), auth.uid()) returning id into v_ev;
  return jsonb_build_object('ok', true, 'kind', 'locked_field_update', 'choice', p_choice, 'ref', p_ref, 'event_id', v_ev, 'returns', v_returns, 'result', jsonb_build_object('applied_id', v_applied));
end $function$;
revoke all on function security.layer4_locked_update_inbox_decide_v1(text, text, text, text) from public, anon;

-- Bulk: the same choice and reason for several items, each decided (and logged) on its own.
CREATE OR REPLACE FUNCTION security.layer4_locked_update_bulk_v1(p_refs text[], p_choice text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ref text; v jsonb; v_ok int := 0; v_out jsonb := '[]'::jsonb; v_max int := security.pipeline_num_v1('layer4.locked_update_bulk_max', 100)::int;
begin
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    return jsonb_build_object('ok', false, 'request', 'Give the reason for this decision; it is kept in the audit log for every item.');
  end if;
  if coalesce(cardinality(p_refs), 0) = 0 then return jsonb_build_object('ok', false, 'request', 'Select at least one item.'); end if;
  if cardinality(p_refs) > v_max then
    return jsonb_build_object('ok', false, 'request', format('Select at most %s items at once (setting layer4.locked_update_bulk_max).', v_max));
  end if;
  foreach v_ref in array p_refs loop
    v := security.layer4_locked_update_inbox_decide_v1(v_ref, p_choice, null, p_reason);
    if (v->>'ok')::boolean then v_ok := v_ok + 1; end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('ref', v_ref, 'ok', v->'ok', 'request', v->'request'));
  end loop;
  return jsonb_build_object('ok', true, 'choice', p_choice, 'decided', v_ok, 'asked', cardinality(p_refs), 'items', v_out);
end $function$;
revoke all on function security.layer4_locked_update_bulk_v1(text[], text, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_layer4_locked_update_bulk(p_refs text[], p_choice text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then  -- fixed: Curator rank, as the Inbox's own decide
    raise exception 'FORBIDDEN: Curator rank or higher is needed' using errcode = '42501';
  end if;
  return security.layer4_locked_update_bulk_v1(p_refs, p_choice, p_reason);
end $function$;
revoke all on function public.admin_layer4_locked_update_bulk(text[], text, text) from public, anon;
grant execute on function public.admin_layer4_locked_update_bulk(text[], text, text) to authenticated;

insert into pipeline.layer4_inbox_kind_hooks(kind, mode, kind_fn, counts_fn, page_fn, detail_fn, decide_fn, enabled, owner, note)
values ('locked_field_update', 'kind', 'security.layer4_locked_update_kind_v1()', 'security.layer4_locked_update_inbox_counts_v1()', 'security.layer4_locked_update_inbox_page_v1(jsonb)',
        'security.layer4_locked_update_inbox_detail_v1(text)', 'security.layer4_locked_update_inbox_decide_v1(text,text,text,text)', true,
        'Human Edits & Periodic Audit (CF-247 s1023)', 'Periodic Audit - Locked Field Update: re-reads of locked tuition and intakes that differ from the live value (Platform Admin 24 Nov 2026, UI-UX plan v1.2 slice 5)')
on conflict do nothing;

do $post$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1023_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1023_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if not exists (select 1 from pipeline.layer4_inbox_kind_hooks where kind = 'locked_field_update' and enabled) then raise exception 'post-check: the Inbox kind is not registered'; end if;
  if position('locked_field_update_raise_v1' in pg_get_functiondef('security.manual_fact_guard'::regproc)) = 0 then raise exception 'post-check: the guard does not record locked re-reads'; end if;
  if (select count(*) from pg_trigger where tgfoid = 'security.manual_fact_guard'::regproc and not tgisinternal) <> 4 then raise exception 'post-check: the guard is not on its four tables'; end if;
end $post$;
