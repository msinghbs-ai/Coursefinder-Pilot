-- CF-247 Layer 4 operational groups (migration 20261104560000; mandate 4 Nov 2026 16:32 §2, §7, §8, §10) on seed.sql. Scratch PostgreSQL 16 only.
\set ON_ERROR_STOP on
select set_config('fx.uid', '63ba56cb-48d4-4169-98c2-7c4d1f72925b', false), set_config('fx.rank', '6', false);
create or replace function pg_temp.g(p_ref text) returns record language sql as $f$ select (grp, cls, rule) from security.layer4_groups_v1() where ref = p_ref $f$;
create or replace function pg_temp.grp(p_ref text) returns text language sql as $f$ select grp from security.layer4_groups_v1() where ref = p_ref $f$;
create or replace function pg_temp.decide(p_kind text, p_ref text, p_choice text, p_reason text default 'Fixture: checked on the stored copy', p_value text default null) returns jsonb language sql as
  $f$ select public.admin_layer4_inbox('decide', jsonb_build_object('kind', p_kind, 'ref', p_ref, 'choice', p_choice, 'reason', p_reason, 'value', p_value)) $f$;

-- G1 four groups from one shared function; A only where an existing rule covers the item (§2)
do $$
declare v jsonb;
begin
  if pg_temp.grp('6e000000-0000-4000-8000-000000000001') <> 'A' or (select rule from security.layer4_groups_v1() where ref = '6e000000-0000-4000-8000-000000000001') not like 'Decision 263 rule%'
    then raise exception 'G1: a Decision 263 pass routed by the Course Link classifier is A, with its authority'; end if;
  if pg_temp.grp('6e000000-0000-4000-8000-000000000002') <> 'A' or (select cls from security.layer4_groups_v1() where ref = '6e000000-0000-4000-8000-000000000002') <> 'course_link:covered_by_active'
    then raise exception 'G1: already active is A'; end if;
  if pg_temp.grp('6e000000-0000-4000-8000-000000000004') <> 'B' or pg_temp.grp('6e000000-0000-4000-8000-000000000005') <> 'C' then raise exception 'G1: invalid link B, judgement ready C'; end if;
  if pg_temp.grp('6e000000-0000-4000-8000-000000000006') <> 'C' or pg_temp.grp('6e000000-0000-4000-8000-000000000007') <> 'B' or pg_temp.grp('6e000000-0000-4000-8000-000000000008') <> 'D'
    then raise exception 'G1: AER ready C, held B, held with human input D'; end if;
  if pg_temp.grp('9911') <> 'C' or pg_temp.grp('6b000000-0000-4000-8000-000000000001') <> 'B' or pg_temp.grp('8901') <> 'D' then raise exception 'G1: scholarship C, adapter B, pages D'; end if;
  if (select count(*) from security.layer4_groups_v1() where grp = 'A' and rule is null) > 0 then raise exception 'G1: an A item without its rule'; end if;
  if (select count(*) from security.layer4_groups_v1()) <> (select count(*) from security.layer4_inbox_items_v2(null, null, null, false))
                                                        + (select count(*) from pipeline.layer4_interventions where status in ('ai_pending', 'awaiting_input', 'resuming'))
    then raise exception 'G1: every waiting item is in exactly one group'; end if;
  v := public.admin_layer4_groups('{}');
  if (v->'groups'->>'A')::int < 3 or v->'labels'->>'C' <> 'Ready for my decision' or v->'labels'->>'D' <> 'Information needed from me' or v->'labels'->>'B' <> 'Technical recovery'
     or jsonb_array_length(v->'rules') < 2 then raise exception 'G1: summary %', v; end if;
  -- without the Course Link classifier, official links stay in C (Integration Controller 4 Nov 2026)
  alter function security.course_link_route_class_v1(uuid) rename to course_link_route_class_v1_off;
  if pg_temp.grp('6e000000-0000-4000-8000-000000000001') <> 'C' or pg_temp.grp('6e000000-0000-4000-8000-000000000004') <> 'C' then raise exception 'G1: router missing'; end if;
  alter function security.course_link_route_class_v1_off(uuid) rename to course_link_route_class_v1;
  raise notice 'G1 ok: % (A rules: %)', v->'groups', (select string_agg(r->>'rule' || ' ' || (r->>'n'), '; ') from jsonb_array_elements(v->'rules') r);
end $$;

-- G2 the three choices page in the Inbox card shape; group A has no cards; one university's page is that university's only (§7)
do $$
declare v jsonb; n int := 0; o int := 0; t int;
begin
  begin perform public.admin_layer4_groups('{"action": "items", "group": "A"}'); raise exception 'G2: A has cards';
  exception when others then if sqlerrm not like 'group A is settled by existing rules%' then raise; end if; end;
  loop
    v := public.admin_layer4_groups(jsonb_build_object('action', 'items', 'group', 'C', 'limit', 5, 'offset', o));
    t := (v->>'total')::int; n := n + jsonb_array_length(v->'items'); o := o + 5;
    if exists (select 1 from jsonb_array_elements(v->'items') x where x->>'group' <> 'C' or not (x ? 'detail') or x->>'kind' is null) then raise exception 'G2: card shape %', v; end if;
    exit when o >= t;
  end loop;
  if n <> t or t <> (select count(*) from security.layer4_groups_v1() where grp = 'C') then raise exception 'G2: paging % of %', n, t; end if;
  v := public.admin_layer4_groups('{"action": "items", "group": "D", "provider_id": "6a000000-0000-4000-8000-000000000001", "limit": 50}');
  if exists (select 1 from jsonb_array_elements(v->'items') x where x->>'provider_id' <> '6a000000-0000-4000-8000-000000000001')
     or not exists (select 1 from jsonb_array_elements(v->'items') x where x->>'kind' = 'intervention' and (x->>'hook')::boolean) then raise exception 'G2: university D page %', v; end if;
  raise notice 'G2 ok: group C pages every item once (% items); a university''s D page holds its Human input needed items; A has no cards', t;
end $$;

-- G3 each card answers the six questions: group and whether a person is needed, evidence, earlier decision (§7, §8)
do $$
declare v jsonb;
begin
  v := (public.admin_layer4_lifecycle(jsonb_build_object('items', jsonb_build_array(jsonb_build_object('kind', 'nothing_ready', 'ref', '6b000000-0000-4000-8000-000000000001'),
        jsonb_build_object('kind', 'course_link', 'ref', '6e000000-0000-4000-8000-000000000003'), jsonb_build_object('kind', 'pages_not_found', 'ref', '8901')))))->'items';
  if v->'nothing_ready:6b000000-0000-4000-8000-000000000001'->>'group_label' <> 'Technical recovery' or v->'nothing_ready:6b000000-0000-4000-8000-000000000001'->'evidence'->>'Pages read' <> '3'
     or v->'nothing_ready:6b000000-0000-4000-8000-000000000001'->'evidence'->'Why each field is held'->>'english' is null then raise exception 'G3: adapter card %', v->'nothing_ready:6b000000-0000-4000-8000-000000000001'; end if;
  if v->'course_link:6e000000-0000-4000-8000-000000000003'->'evidence'->'Settled before'->>'Covered by item' <> '6e000000-0000-4000-8000-000000000010'
     or v->'course_link:6e000000-0000-4000-8000-000000000003'->>'person_needed' not like 'no:%' then raise exception 'G3: re-raised card %', v->'course_link:6e000000-0000-4000-8000-000000000003'; end if;
  if v->'pages_not_found:8901'->'evidence'->>'How it was looked for' <> 'map(0)+map_search(0)' or v->'pages_not_found:8901'->>'group' <> 'D' then raise exception 'G3: page hold card'; end if;
  if v->'nothing_ready:6b000000-0000-4000-8000-000000000001'->>'why_pending' is null or v->'nothing_ready:6b000000-0000-4000-8000-000000000001'->'times'->'first_entered' is null
    then raise exception 'G3: the lifecycle answers stay'; end if;
  raise notice 'G3 ok: cards carry their group and the person question; adapter and page cards show the evidence held; a re-raised item names the earlier decision';
end $$;

-- G4 duplicates do not produce duplicate decisions; a decision that did not apply is recorded as not applied (§8; §10.4)
do $$
declare r1 jsonb; r2 jsonb; n int;
begin
  r1 := pg_temp.decide('held_scholarship', '9911', 'not_international', 'Fixture batch [fx-not-applied]');
  if r1->'ack'->>'outcome' <> 'incomplete' or (r1->'result'->>'still_waiting')::boolean is not true then raise exception 'G4: not applied recorded as done %', r1->'ack'; end if;
  r2 := pg_temp.decide('held_scholarship', '9911', 'not_international', 'Fixture batch, sent again');
  if r2->'ack'->>'outcome' <> 'completed' or (select status from pipeline.scholarship_ai_reviews where id = 9911) <> 'refused' then raise exception 'G4: the retry after a non-applied send applies %', r2->'ack'; end if;
  -- a decided item refuses another decision (the 96: the second call of the batch is refused once the first has applied)
  begin perform pg_temp.decide('held_scholarship', '9911', 'not_international', 'Fixture batch, third'); raise exception 'G4: decided twice';
  exception when others then if sqlerrm not like '%no longer waiting%' then raise; end if; end;
  if (select count(*) from pipeline.admin_control_events where target = 'held_scholarship:9911' and action = 'inbox_decide' and detail->'result'->>'still_waiting' = 'false') <> 1
    then raise exception 'G4: exactly one applied decision'; end if;
  raise notice 'G4 ok: a decision that did not apply is "Still incomplete" (still_waiting), the next one applies, a decided item refuses another: one applied decision';
end $$;
do $$
declare r jsonb; n int;
begin
  -- the same choice twice inside the window on a waiting item: the second returns the first (Keep waiting leaves the hold waiting)
  insert into pipeline.enrichment_flags(id, entity, entity_key, provider_id, state, reason_code, reason, evidence, flagged_at)
  values (8902, 'provider', '6a000000-0000-4000-8000-000000000002', '6a000000-0000-4000-8000-000000000002', 'raised', 'site_unreachable', 'down', '{}', now() - interval '40 days');
  r := pg_temp.decide('site_down', '8902', 'wait');
  n := (select count(*) from pipeline.admin_control_events where target = 'site_down:8902' and action = 'inbox_decide');
  update pipeline.enrichment_flags set flagged_at = now() - interval '40 days' where id = 8902;  -- still listed
  r := pg_temp.decide('site_down', '8902', 'wait');
  if (r->>'ok')::boolean or r->'ack'->>'headline' <> 'Already sent — the first decision stands'
     or (select count(*) from pipeline.admin_control_events where target = 'site_down:8902' and action = 'inbox_decide') <> n
     or not exists (select 1 from pipeline.admin_control_events where target = 'site_down:8902' and action = 'inbox_refused') then raise exception 'G4b: %', r; end if;
  raise notice 'G4b ok: the same decision sent again inside the window returns the first (audited as refused, never taken twice)';
end $$;

-- G5 retry guards: retry and rebuild at most once on an unchanged stop; a changed university may try again (§8; §10.3, §10.5)
do $$
declare r jsonb;
begin
  r := pg_temp.decide('nothing_ready', '6b000000-0000-4000-8000-000000000001', 'rebuild');
  if not (r->>'ok')::boolean then raise exception 'G5: first rebuild %', r; end if;
  -- the rebuild stopped the same way: a new item for the same university and stop
  insert into pipeline.provider_onboarding(id, provider_id, status, stop_reason, note, created_at, updated_at, result)
  values ('6b000000-0000-4000-8000-000000000011', '6a000000-0000-4000-8000-000000000003', 'stopped', 'nothing_ready', 'Nothing passed after 2 AI attempt(s)', now(), now(), '{"courses": 11, "pages_read": 3}');
  update pipeline.provider_onboarding set status = 'superseded' where id = '6b000000-0000-4000-8000-000000000001';
  r := pg_temp.decide('nothing_ready', '6b000000-0000-4000-8000-000000000011', 'rebuild');
  if (r->>'ok')::boolean or r->'ack'->>'headline' <> 'Not tried again — the same stop, nothing changed' or r->>'request' not like 'Not tried again: rebuild was already taken for this university at %'
     or r->'ack'->>'alternative' not like 'Open the adapter in the builder%' then raise exception 'G5: second rebuild %', r; end if;
  if (public.admin_layer4_lifecycle('{"kind": "nothing_ready", "ref": "6b000000-0000-4000-8000-000000000011"}'))->'last_action'->'result'->>'headline' <> 'Not tried again — the same stop, nothing changed'
    then raise exception 'G5: the refusal is not on the card after Refresh'; end if;
  -- the university changed (a new website): one more try is allowed
  update catalogue.providers set website = 'https://www.astra.edu.au', updated_at = now() + interval '1 second' where id = '6a000000-0000-4000-8000-000000000003';
  if security.layer4_decide_guard_v1('nothing_ready', '6b000000-0000-4000-8000-000000000011', 'rebuild', '6a000000-0000-4000-8000-000000000003') is not null then raise exception 'G5: change re-opens'; end if;
  -- a transient proposal failure keeps its one retry (bounded)
  r := pg_temp.decide('onboarding_failed', '6b000000-0000-4000-8000-000000000002', 'retry');
  if not (r->>'ok')::boolean then raise exception 'G5: first retry %', r; end if;
  raise notice 'G5 ok: rebuild once; the same stop with nothing changed is refused with the reason and the alternatives (on the card after Refresh); a changed university may try again; a retry keeps its one attempt';
end $$;

-- G6 a choice that opens another screen is audited; the card shows it (§8)
do $$
declare r jsonb; v jsonb;
begin
  r := public.admin_layer4_navigate('{"kind": "too_few_pages", "ref": "5b000000-0000-4000-8000-000000000002", "choice": "pages"}');
  if not (r->>'ok')::boolean then raise exception 'G6: %', r; end if;
  v := public.admin_layer4_lifecycle('{"kind": "too_few_pages", "ref": "5b000000-0000-4000-8000-000000000002"}');
  if v->'last_action'->'result'->>'headline' not like 'Opened the adapter builder — __:__ AE_T: the item closes when the work there is saved' then raise exception 'G6: card %', v->'last_action'; end if;
  begin perform public.admin_layer4_navigate('{"kind": "held_scholarship", "ref": "9912", "choice": "publish"}'); raise exception 'G6: a deciding choice logged as navigation';
  exception when others then if sqlerrm not like 'this choice does not open another screen%' then raise; end if; end;
  raise notice 'G6 ok: opening the builder is audited (inbox_navigate) and shown on the card; a deciding choice cannot be logged as navigation';
end $$;

-- G7 human input resumes the original work and other universities continue (§10.6, §10.10)
do $$
declare i bigint := (select id from pipeline.layer4_interventions where entity = '6e000000-0000-4000-8000-000000000008');
begin
  update pipeline.layer4_interventions set status = 'resuming', input_at = now(), resumed_at = now() where id = i;  -- as security.layer4_intervention_resolve_v1 leaves it
  if pg_temp.grp('6e000000-0000-4000-8000-000000000008') <> 'B' or pg_temp.grp(i::text) <> 'B' then raise exception 'G7: input given moves the read to technical recovery (resuming)'; end if;
  if pg_temp.grp('6e000000-0000-4000-8000-000000000009') <> 'C' then raise exception 'G7: another university''s ready item'; end if;
  raise notice 'G7 ok: once input is given the held read and its item move to technical recovery (resuming); another university''s ready read stays ready';
end $$;

-- G8 one page of each choice within the Inbox's first-read budget
do $$
declare t timestamptz; ms numeric; g text;
begin
  foreach g in array array['C', 'D', 'B'] loop
    t := clock_timestamp(); perform public.admin_layer4_groups(jsonb_build_object('action', 'items', 'group', g, 'limit', 25)); ms := extract(epoch from clock_timestamp() - t) * 1000;
    if ms > 300 then raise exception 'G8: % page took % ms', g, round(ms); end if;
  end loop;
  t := clock_timestamp(); perform public.admin_layer4_groups('{}'); ms := extract(epoch from clock_timestamp() - t) * 1000;
  raise notice 'G8 ok: summary % ms; a page of each choice under 300 ms', round(ms);
end $$;
