-- CF-247 / Decision 160 follow-up: open Layer 3 tuition items were still assigned to the retired Nemotron
-- profile (disabled, paused, benchmark failed), so the dispatcher, which only reserves items for the profile
-- it runs, never picked them up. Open items (pending or failed, never finished ones) on a profile that cannot
-- run are moved to the single qualified, active profile for the same task class. Each move is recorded.
-- Results are bound to the profile that actually runs the item, so nothing already decided changes.

create table if not exists pipeline.layer3_work_item_rebinds(
  id bigint generated always as identity primary key,
  work_item_id uuid not null references pipeline.layer3_work_items(id) on delete cascade,
  from_profile_id uuid not null references pipeline.layer3_model_profiles(id),
  to_profile_id uuid not null references pipeline.layer3_model_profiles(id),
  status_at_move text not null,
  reason text not null,
  actor_id uuid not null,
  change_control_ref text not null default 'CF-CHG-20260915-247',
  created_at timestamptz not null default now());
alter table pipeline.layer3_work_item_rebinds enable row level security;
revoke all on pipeline.layer3_work_item_rebinds from public, anon, authenticated;

do $rebind$
declare v_to uuid; v_n int; v_moved int;
begin
  select count(*), min(id::text)::uuid into v_n, v_to from pipeline.layer3_model_profiles
   where enabled and not paused and coalesce((quality_benchmark->>'pass')::boolean,false)
     and 'provider_current_tuition_validation'=any(allowed_task_classes);
  if v_n<>1 then raise exception 'expected exactly one qualified active tuition profile, found %', v_n; end if;

  with moved as (
    update pipeline.layer3_work_items w set profile_id=v_to, updated_at=now(),
           last_error=left(coalesce(w.last_error,'')||' | Moved to the qualified profile (Decision 160)',1000)
      from pipeline.layer3_model_profiles p
     where p.id=w.profile_id and w.profile_id<>v_to
       and w.task_class='provider_current_tuition_validation'
       and w.status in ('pending','failed')
       and (not p.enabled or p.paused)
    returning w.id, p.id from_id, w.status)
  insert into pipeline.layer3_work_item_rebinds(work_item_id,from_profile_id,to_profile_id,status_at_move,reason,actor_id)
  select id, from_id, v_to, status, 'Assigned profile cannot run; moved to the qualified active profile (Decision 160)',
         'c0ffee00-0000-4000-8000-000000000150'::uuid from moved;
  get diagnostics v_moved = row_count;
  raise notice 'moved % open item(s) to %', v_moved, v_to;
end $rebind$;
