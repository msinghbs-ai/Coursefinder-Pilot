-- CF-247 s1165 (S1-RM-Design; Global Autonomous PIM step 2, the safe replacement guard; Master Plan section 6.3 and Platform Admin 25 Nov 2026 18:49:
-- "Safe replacement guard: no supersession without a verified successor in the same transaction, else HELD:NO_SUCCESSOR").
--   1. security.supersede_guard_v1(p_course, p_fee_type, p_row) says whether a fee row may stop being current: true only when another active row of the same course and
--      fee type stays (the verified successor, already admitted), or the course is no longer active (an archived course has nothing to replace).
--   2. One deferred constraint trigger on catalogue.course_fees checks every row that goes from active to superseded when the transaction commits, so a writer may insert its
--      successor before or after the supersession in the same transaction. No successor: the transaction stops with HELD:NO_SUCCESSOR and the old value stays current.
--   Why only fees: superseded is the status that means "replaced by a newer value". English requirements and intakes leave current as withdrawn, entry requirements as inactive,
--   and those are removals, which stay under the bulk-withdrawal rule (escalation item e). Live read before writing: of 97,833 superseded fee rows, 27 (all dated 4 to 8 Oct 2026,
--   none since) have no active row of the same fee type, so the writers now in use all keep a successor.
-- G1: no job. G2: no operational value. G3: no consumer API object altered (the trigger adds no column and changes no shape; checked before and after). Locks and cron unchanged.
-- Replaces: none. Retires: none.
set local lock_timeout = '5s';  -- fixed: lock wait for the trigger create
set local statement_timeout = '120s';  -- fixed: the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1165_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1165_cron on commit drop as select count(*) n from cron.job where active;

create or replace function security.supersede_guard_v1(p_course uuid, p_fee_type text, p_row uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare v_active boolean; v_next int;
begin
  select (c.lifecycle_status = 'active') into v_active from catalogue.courses c where c.id = p_course;
  if v_active is distinct from true then
    return jsonb_build_object('ok', true, 'reason', 'course_not_active', 'successors', 0);
  end if;
  select count(*) into v_next from catalogue.course_fees a
   where a.course_id = p_course and a.fee_type = p_fee_type and a.status = 'active' and a.id is distinct from p_row;
  if v_next = 0 then
    return jsonb_build_object('ok', false, 'held', 'NO_SUCCESSOR', 'successors', 0);
  end if;
  return jsonb_build_object('ok', true, 'reason', 'successor_active', 'successors', v_next);
end $f$;
comment on function security.supersede_guard_v1(uuid, text, uuid) is 'Replacement guard (s1165): ok when another active fee of the same course and type stays, or the course is not active; otherwise held NO_SUCCESSOR.';
revoke all on function security.supersede_guard_v1(uuid, text, uuid) from public, anon, authenticated;
grant execute on function security.supersede_guard_v1(uuid, text, uuid) to service_role;

create or replace function security.course_fee_supersede_guard_tg()
returns trigger
language plpgsql
security definer
set search_path = ''
as $f$
declare g jsonb;
begin
  g := security.supersede_guard_v1(new.course_id, new.fee_type, new.id);
  if (g->>'ok')::boolean is not true then
    raise exception 'HELD:NO_SUCCESSOR: fee % of course % (%) cannot be superseded without an active successor of the same fee type', new.id, new.course_id, new.fee_type
      using errcode = 'P0001';
  end if;
  return null;
end $f$;
comment on function security.course_fee_supersede_guard_tg() is 'Deferred constraint trigger function (s1165): a fee row that goes from active to superseded needs an active successor when the transaction commits.';
revoke all on function security.course_fee_supersede_guard_tg() from public, anon, authenticated;

create constraint trigger course_fee_supersede_successor
  after update of status on catalogue.course_fees
  deferrable initially deferred
  for each row
  when (old.status = 'active' and new.status = 'superseded')
  execute function security.course_fee_supersede_guard_tg();

do $c$
declare v jsonb := security.consumer_api_check_v1(); g jsonb; r record; v_n int;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1165_locks) then raise exception 'guard: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1165_cron) then raise exception 'guard: active cron jobs changed'; end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'catalogue.course_fees'::regclass and t.tgname = 'course_fee_supersede_successor' and t.tgdeferrable and t.tginitdeferred) then
    raise exception 'guard: the deferred constraint trigger is not in place';
  end if;
  -- a course whose only active fee of a type is this row: held. Read only, no live row is changed.
  select f.* into r from catalogue.course_fees f join catalogue.courses c on c.id = f.course_id and c.lifecycle_status = 'active'
   where f.status = 'active' and f.fee_type = 'provider_current_tuition'
     and (select count(*) from catalogue.course_fees a where a.course_id = f.course_id and a.fee_type = f.fee_type and a.status = 'active') = 1
   order by f.id limit 1;  -- fixed: one sample row for the rehearsal
  if r.id is not null then
    g := security.supersede_guard_v1(r.course_id, r.fee_type, r.id);
    if g->>'held' is distinct from 'NO_SUCCESSOR' then raise exception 'guard: a sole active fee was not held: %', g; end if;
    g := security.supersede_guard_v1(r.course_id, r.fee_type, gen_random_uuid());
    if (g->>'ok')::boolean is not true then raise exception 'guard: a fee with another active row was held: %', g; end if;
  end if;
  -- an unknown course has nothing to replace
  g := security.supersede_guard_v1(gen_random_uuid(), 'tuition', gen_random_uuid());
  if (g->>'ok')::boolean is not true then raise exception 'guard: an unknown course was held: %', g; end if;
  -- the live superseded rows are unchanged by this change
  select count(*) into v_n from catalogue.course_fees where status = 'superseded';
  if v_n < 97000 then raise exception 'guard: superseded fee rows fell to %', v_n; end if;  -- fixed: a floor of the live count at write time (97,833)
end $c$;
