-- Added to ../aer-source-recovery/stubs.sql: only what security.aer_schedule_held_v1 reads. The E13 gate, the shared recovery rule and the correction check are
-- driven by the fixture table fx.item_state, one row per waiting item (the real functions are covered by their own fixtures).
create schema if not exists fx;
create table fx.item_state (item_id uuid primary key, gate jsonb not null, rule jsonb not null, check_ok boolean not null default true);
alter table pipeline.coverage_course_pages add column if not exists url text;
alter table pipeline.layer4_review_items add column if not exists created_at timestamptz default now();
create table if not exists pipeline.aer_read_supersessions (id bigserial primary key, old_item_id uuid, state text, requested_at timestamptz default now());
drop function security.aer_schedule_held_v1(int);
create function security.aer_schedule_country_v1(p text) returns jsonb language sql stable as $$ select jsonb_build_object('on', true) $$;
create function security.course_entry_gate_v1(p uuid) returns jsonb language sql stable as $$ select gate from fx.item_state where item_id = p $$;
create function security.aer_recovery_rule_v1(p uuid) returns jsonb language sql stable as $$ select rule from fx.item_state where item_id = p $$;
create function security.course_entry_correction_check_v1(p uuid, c uuid, u text) returns jsonb language sql stable as $$ select jsonb_build_object('ok', check_ok, 'why', case when not check_ok then 'fixture: not correctable' end) from fx.item_state where item_id = p $$;
-- security.aer_parked_items_v1 as migration 20261110160000 creates it (the tick counts parked holds apart)
create function security.aer_parked_items_v1() returns table(item_id uuid, provider_id uuid, field_code text, failure_class text, reason text, next_action text, parked_since timestamptz)
language sql stable as $f$
  select i.id, w.provider_id, i.field_code, w.failure_class, w.unresolved_blocker->>'reason', w.unresolved_blocker->>'next_action', null::timestamptz
    from pipeline.work_items w join pipeline.layer4_review_items i on i.id::text = w.entity
   where w.lane = 'aer_technical' and w.work_kind = 'l4_item' and w.stage = 'parked' and w.unresolved_blocker->>'action' = 'park'
     and i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')
$f$;
