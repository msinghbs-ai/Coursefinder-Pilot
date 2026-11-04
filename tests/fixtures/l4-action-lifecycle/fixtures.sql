-- CF-247 Layer 4 action lifecycle (migration 20261104540000; Platform Admin decision 4 Nov 2026 12:24): the §9 cases end to end on seed.sql.
-- Scratch PostgreSQL 16 only.
\set ON_ERROR_STOP on
create or replace function pg_temp.as_user(p_uid text, p_rank int) returns void language sql as
  $f$ select set_config('fx.uid', coalesce(p_uid, ''), false), set_config('fx.rank', coalesce(p_rank::text, ''), false) $f$;
create or replace function pg_temp.lc(p_kind text, p_ref text) returns jsonb language sql as $f$ select security.layer4_item_lifecycle_v1(p_kind, p_ref) $f$;
create or replace function pg_temp.decide(p_kind text, p_ref text, p_choice text, p_reason text default 'Fixture: checked on the stored copy', p_value text default null) returns jsonb language sql as
  $f$ select public.admin_layer4_inbox('decide', jsonb_build_object('kind', p_kind, 'ref', p_ref, 'choice', p_choice, 'reason', p_reason, 'value', p_value)) $f$;
select pg_temp.as_user('63ba56cb-48d4-4169-98c2-7c4d1f72925b', 6);

-- C1 RMIT Diploma of Commerce (IQ-00279): the click is traceable, the refusal is shown, the identical read is neither offered nor run
do $$
declare v jsonb; d jsonb; r jsonb; n_sup int := (select count(*) from pipeline.aer_read_supersessions); n_fei int := (select count(*) from pipeline.field_enrich_items);
        v_ref text := 'a7849f66-bfa7-412e-b26e-4fecc7fdaa6e';
begin
  v := pg_temp.lc('aer_review', v_ref);
  if v->>'stage' <> 'failed' or v->>'status' <> 'pending' or v->'steps'->>'requested' <> 'yes' or v->'steps'->>'valid' not like 'no: the corrected read was cut at the row limit%'
     or v->'steps'->>'executed' not like 'yes, Wed 4 Nov 2026, 12:18 pm AEDT' then raise exception 'C1: lifecycle %', v - 'history'; end if;
  if v->'times'->'first_entered'->>'text' <> 'Thu 29 Oct 2026, 12:44 pm AEDT' or v->'times'->'last_reviewer_action'->>'text' <> 'Wed 4 Nov 2026, 12:17 pm AEDT'
     then raise exception 'C1: times %', v->'times'; end if;
  if v->'last_action'->>'ref' <> 'audit #28863' or (select count(*) from jsonb_array_elements(v->'history') h where h->>'action' = 'corrected read') <> 2 then raise exception 'C1: history %', v->'history'; end if;
  if v->'repeat_guard' is null or v->'next'->>'text' not like 'Open human input%row limit for this university%' then raise exception 'C1: repeat guard %', v->'repeat_guard'; end if;
  d := security.layer4_aer_recovery_detail_v1(v_ref);
  if (select (a->>'allowed')::boolean from jsonb_array_elements(d->'actions') a where a->>'key' = 'reread_stored') or d->'sections'->0->'body'->>'Recommended recovery' <> 'open_intervention'
     or d->'sections'->1->'body'->>'Reader result' <> 'the corrected read was cut at the row limit (E13)' or (d->'sections'->1->'body'->>'Refusals on this copy')::int <> 2
     then raise exception 'C1: recovery panel %', d; end if;
  -- the same click again: already requested, with the original action and its current state; nothing is read
  r := pg_temp.decide('aer_review', v_ref, 'reread_stored');
  if (r->>'ok')::boolean or r->'ack'->>'outcome' <> 'already_requested' or r->>'request' not like 'Already requested: recovery action % at Wed 4 Nov 2026, 12:17 pm AEDT. Now: the reader refused it at Wed 4 Nov 2026, 12:18 pm AEDT: the corrected read was cut at the row limit (E13).%'
     or r->>'request' not like '%would be refused the same way%' or r->'ack'->>'ref' is null or r->'ack'->'at'->>'text' not like '% AEDT' or r->'ack'->>'alternative' not like 'Open human input%'
     then raise exception 'C1: duplicate reply %', r; end if;
  if (select count(*) from pipeline.aer_read_supersessions) <> n_sup or (select count(*) from pipeline.field_enrich_items) <> n_fei then raise exception 'C1: a read was started'; end if;
  -- Refresh: the card reads the same acknowledgement back from the audit row
  v := pg_temp.lc('aer_review', v_ref);
  if v->'last_action'->>'ref' <> r->'ack'->>'ref' or v->'last_action'->'result'->>'outcome' <> 'already_requested' then raise exception 'C1: refresh lost the acknowledgement %', v->'last_action'; end if;
  raise notice 'C1 ok: RMIT: requested 12:17 pm AEDT (audit #28863), executed 12:18 pm, refused (row limit), still pending since 29 Oct 12:44 pm; the same read is not offered, a second click names the original action and its refusal and reads nothing';
end $$;

-- C2 re-read refused (deterministic repeat) on an item without an earlier recovery action, and allowed again after a real change
do $$
declare r jsonb; v_ref text := '5e000000-0000-4000-8000-000000000002'; v_e bigint; n int;
begin
  r := pg_temp.decide('aer_review', v_ref, 'reread_stored');
  if not (r->>'ok')::boolean or r->'ack'->>'outcome' <> 'queued' or r->'ack'->>'stage' <> 'scheduled' or r->'ack'->>'next' not like 'the entry reader reads the stored copy (job %' then raise exception 'C2: accepted %', r->'ack'; end if;
  v_e := (r->'result'->'detail'->>'enrich_item_id')::bigint;
  -- C2a Refresh during the asynchronous read: scheduled, then running, from the persisted records
  if pg_temp.lc('aer_review', v_ref)->>'stage' <> 'scheduled' then raise exception 'C2a: refresh while queued'; end if;
  update pipeline.field_enrich_items set state = 'leased' where id = v_e;
  if pg_temp.lc('aer_review', v_ref)->>'stage' <> 'executing' or pg_temp.lc('aer_review', v_ref)->'steps'->>'executed' <> 'running' then raise exception 'C2a: refresh while running'; end if;
  -- C2b accepted but still incomplete: the reader refuses; the item stays pending with the remaining failure and the next action
  perform fx.reader(v_e, 'refused', 'the corrected read still drops 2 printed requirement(s)');
  r := pg_temp.lc('aer_review', v_ref);
  if r->>'stage' <> 'failed' or r->>'why_pending' not like '%still drops 2 printed requirement(s)%' or r->'repeat_guard' is null or r->'next'->>'text' not like 'Open human input%Request official evidence' then raise exception 'C2b: %', r - 'history'; end if;
  -- C2c the identical read is refused by the decide function, recorded with its reason; nothing is read
  n := (select count(*) from pipeline.aer_read_supersessions);
  delete from pipeline.layer4_aer_recovery_actions where review_item_id = v_ref::uuid;  -- as if the first read had come from the scheduled job (no recovery row)
  r := pg_temp.decide('aer_review', v_ref, 'reread_stored');
  if (r->>'ok')::boolean or r->'ack'->>'outcome' <> 'refused' or r->>'request' not like 'Not read again: the reader refused the corrected read of this stored copy at %. Instead: Open human input%'
     or (select count(*) from pipeline.aer_read_supersessions) <> n then raise exception 'C2c: %', r; end if;
  if not exists (select 1 from pipeline.layer4_aer_recovery_actions a where a.review_item_id = v_ref::uuid and a.result->>'repeat_of' is not null) then raise exception 'C2c: the refusal is not recorded'; end if;
  if pg_temp.lc('aer_review', v_ref)->'last_action'->'result'->>'outcome' <> 'refused' then raise exception 'C2c: the card does not show the refusal after refresh'; end if;
  -- C2d a reader correction (layer4.reader_revision) or a new stored copy makes the read worth asking again
  update pipeline.platform_toolset_settings set value = to_jsonb(2), updated_at = clock_timestamp() + interval '1 second' where toolset_key = 'pipeline' and key = 'layer4.reader_revision';
  if (security.layer4_reread_repeat_v1(v_ref::uuid)->>'repeat')::boolean
     or not (select (a->>'allowed')::boolean from jsonb_array_elements(security.layer4_aer_recovery_detail_v1(v_ref)->'actions') a where a->>'key' = 'reread_stored') then raise exception 'C2d: reader change'; end if;
  update pipeline.platform_toolset_settings set updated_at = '2026-10-01' where toolset_key = 'pipeline' and key = 'layer4.reader_revision';
  if not (security.layer4_reread_repeat_v1(v_ref::uuid)->>'repeat')::boolean then raise exception 'C2d: unchanged again'; end if;
  update pipeline.coverage_course_pages set evidence_id = md5('copy:new')::uuid where course_id = '5c000000-0000-4000-8000-000000000002';
  if (security.layer4_reread_repeat_v1(v_ref::uuid)->>'repeat')::boolean then raise exception 'C2d: new copy'; end if;
  raise notice 'C2 ok: accepted (queued, job named), scheduled then running on Refresh, refused by the reader and still pending with the reason; the identical read refused and recorded; a reader revision or a new copy re-opens it';
end $$;

-- C3 duplicate request: Open human input twice gives the original reference and its current state
do $$
declare r1 jsonb; r2 jsonb; v_ref text := '5e000000-0000-4000-8000-000000000004'; n int;
begin
  r1 := pg_temp.decide('aer_review', v_ref, 'open_intervention');
  if not (r1->>'ok')::boolean or r1->'ack'->>'outcome' <> 'human_input' or r1->'ack'->>'intervention_id' is null then raise exception 'C3: first %', r1->'ack'; end if;
  n := (select count(*) from pipeline.layer4_interventions);
  r2 := pg_temp.decide('aer_review', v_ref, 'open_intervention');
  if (r2->>'ok')::boolean or r2->'ack'->>'outcome' <> 'already_requested' or r2->>'request' not like 'Already requested: recovery action % Now: Human input needed item % is awaiting input.%'
     or (select count(*) from pipeline.layer4_interventions) <> n then raise exception 'C3: duplicate %', r2; end if;
  if pg_temp.lc('aer_review', v_ref)->>'stage' <> 'awaiting_input' or pg_temp.lc('aer_review', v_ref)->'next'->>'text' not like 'Human input needed item % waits for a person%' then raise exception 'C3: lifecycle'; end if;
  raise notice 'C3 ok: the first request opens Human input needed (linked), the second names the original action and the item''s current state and opens nothing';
end $$;

-- C4 successful corrected read and the superseded item: linked both ways; the new read keeps the original age
do $$
declare r jsonb; v_old text := '5e000000-0000-4000-8000-000000000005'; v_new uuid; o jsonb; n jsonb;
begin
  r := pg_temp.decide('aer_review', v_old, 'reread_stored');
  v_new := fx.reader((r->'result'->'detail'->>'enrich_item_id')::bigint, 'superseded', null);
  o := pg_temp.lc('aer_review', v_old); n := pg_temp.lc('aer_review', v_new::text);
  if o->>'stage' <> 'superseded' or o->>'open' <> 'false' or o->'successor'->>'ref' <> v_new::text or o->'steps'->>'valid' <> 'yes (complete)' then raise exception 'C4: original %', o - 'history'; end if;
  if n->'predecessor'->>'ref' <> v_old or n->'times'->'first_entered'->>'at' <> o->'times'->'first_entered'->>'at' or n->'times'->'item_created'->>'at' = n->'times'->'first_entered'->>'at'
     or n->>'stage' <> 'awaiting_decision' then raise exception 'C4: new read %', n - 'history'; end if;
  raise notice 'C4 ok: the corrected read replaced the original (superseded, linked to its successor); the new read names its predecessor and keeps the first-entered time';
end $$;

-- C5 role-disabled action: refused before anything is written, and the lifecycle read needs Curator
do $$
declare n bigint := (select count(*) from pipeline.admin_control_events);
begin
  perform pg_temp.as_user('63ba56cb-48d4-4169-98c2-7c4d1f72925b', 3);
  begin perform pg_temp.decide('aer_review', '5e000000-0000-4000-8000-000000000009', 'approve'); raise exception 'C5: rank 3 approved';
  exception when others then if sqlerrm not like '%your role cannot make this choice%' then raise; end if; end;
  begin perform pg_temp.decide('aer_review', '5e000000-0000-4000-8000-000000000009', 'reread_stored'); raise exception 'C5: rank 3 re-read';
  exception when others then if sqlerrm not like '%your role cannot%' then raise; end if; end;
  if (public.admin_layer4_lifecycle('{"kind": "aer_review", "ref": "5e000000-0000-4000-8000-000000000009"}'))->>'found' <> 'true' then raise exception 'C5: Curator read'; end if;
  perform pg_temp.as_user('63ba56cb-48d4-4169-98c2-7c4d1f72925b', 2);
  begin perform public.admin_layer4_lifecycle('{"kind": "aer_review", "ref": "5e000000-0000-4000-8000-000000000009"}'); raise exception 'C5: rank 2 read';
  exception when others then if sqlerrm not like '%Curator role or above required%' then raise; end if; end;
  perform pg_temp.as_user('63ba56cb-48d4-4169-98c2-7c4d1f72925b', 6);
  if (select count(*) from pipeline.admin_control_events) <> n then raise exception 'C5: a refused role wrote an audit row'; end if;
  raise notice 'C5 ok: a role-disabled choice is refused before anything is written; the lifecycle read needs Curator (rank 3)';
end $$;

-- C6 admission and publication are separate steps from the decision
do $$
declare v jsonb := pg_temp.lc('aer_review', '5e000000-0000-4000-8000-000000000008');
begin
  if v->>'stage' <> 'resolved' or v->'steps'->>'approved' <> 'yes' or v->'steps'->>'admitted' <> 'yes: 2 rows active' or v->'steps'->>'published' <> 'yes: course and university published'
     or v->'times'->'decided' is null or v->'times'->'admitted' is null or v->'times'->'published' is null then raise exception 'C6: %', v - 'history'; end if;
  update catalogue.providers set publication_status = 'unpublished' where id = '5a000000-0000-4000-8000-000000000001';
  if pg_temp.lc('aer_review', '5e000000-0000-4000-8000-000000000008')->'steps'->>'published' <> 'no: the course or its university is not published' then raise exception 'C6: unpublished university'; end if;
  update catalogue.providers set publication_status = 'published' where id = '5a000000-0000-4000-8000-000000000001';
  raise notice 'C6 ok: approved, admitted (2 rows active) and published are reported separately, with their times; an unpublished university is not counted as published';
end $$;

-- C7 re-entry after technical recovery: the second read counts as a re-entry and keeps the first-entered time
do $$
declare v jsonb := pg_temp.lc('aer_review', '5e000000-0000-4000-8000-000000000009');
begin
  if (v->>'entries')::int <> 2 or (v->'times'->'first_entered'->>'at')::timestamptz > now() - interval '9 days' or (v->'times'->'last_entered'->>'at')::timestamptz < now() - interval '2 days'
     then raise exception 'C7: %', v->'times'; end if;
  raise notice 'C7 ok: re-entered (2 entries); first entered 10 days ago, last entered 1 day ago';
end $$;

-- C8 a built-in decision carries the acknowledgement too; Keep waiting does not reset the first-entered time
do $$
declare r jsonb; v jsonb; v_before timestamptz := (select flagged_at from pipeline.enrichment_flags where id = 8802);
begin
  r := pg_temp.decide('site_down', '8802', 'wait');
  if not (r->>'ok')::boolean or r->'ack'->>'outcome' <> 'accepted' or r->'ack'->>'ref' <> 'audit #' || (r->>'event_id') then raise exception 'C8: %', r; end if;
  v := pg_temp.lc('site_down', '8802');
  if (v->'times'->'first_entered'->>'at')::timestamptz > v_before + interval '1 second' or v->'last_action'->>'action' <> 'wait' then raise exception 'C8: first entered reset by Keep waiting %', v->'times'; end if;
  raise notice 'C8 ok: a built-in decision replies with its acknowledgement (accepted, audit ref, time); Keep waiting moves the asked-again time but not the first entry';
end $$;

-- C9 every kind of the Inbox has a lifecycle with its times; one page in one read
do $$
declare k record; v jsonb; n int := 0; v_items jsonb; t timestamptz;
begin
  for k in select i.kind, i.ref from security.layer4_inbox_items_v2(null, null, null, false) i
            union all select 'intervention', x.id::text from pipeline.layer4_interventions x where x.status = 'awaiting_input' loop
    v := pg_temp.lc(k.kind, k.ref);
    if not (v->>'found')::boolean or v->'times'->'first_entered' is null or v->'times'->'item_created' is null or v->>'stage_label' is null
       or (v->>'open')::boolean and v->>'why_pending' is null then raise exception 'C9: % % %', k.kind, k.ref, v - 'history'; end if;
    n := n + 1;
  end loop;
  -- every kind but Website not answering, which C8 put back to waiting (asked again after the waiting period)
  if (select count(distinct kind) from security.layer4_inbox_items_v2(null, null, null, false)) < 17 then
    raise exception 'C9: the seed covers % kinds', (select array_agg(distinct kind) from security.layer4_inbox_items_v2(null, null, null, false)); end if;
  v_items := (select jsonb_agg(jsonb_build_object('kind', i.kind, 'ref', i.ref)) from security.layer4_inbox_items_v2(null, null, null, false) i);
  t := clock_timestamp();
  v := public.admin_layer4_lifecycle(jsonb_build_object('items', v_items));
  if (select count(*) from jsonb_object_keys(v->'items')) <> least(jsonb_array_length(v_items), 50) then raise exception 'C9: page read %', (select count(*) from jsonb_object_keys(v->'items')); end if;
  raise notice 'C9 ok: % items over every kind (% kinds and Human input needed) have a lifecycle, times and a reason; a page of % in % ms',
    n, (select count(distinct kind) from security.layer4_inbox_items_v2(null, null, null, false)), jsonb_array_length(v_items), round(extract(epoch from clock_timestamp() - t) * 1000);
end $$;

-- C10 the measures (§10)
do $$
declare v jsonb := security.layer4_lifecycle_report_v1();
begin
  if (v->'corrected_reads'->>'refused')::int < 2 or (v->'corrected_reads'->>'repeated_no_yield')::int < 1 or (v->'actions'->>'already_requested')::int < 2
     or (v->'actions'->>'refused')::int < 1 or (v->>'re_entered')::int < 1 then raise exception 'C10: %', v; end if;
  raise notice 'C10 ok: %', v;
end $$;
