-- CF-CHG-20260910-093
-- Runtime observability correction: Layer 2 discovery terminal rows must carry a real completion timestamp.
-- Forward-only. Stamps a timestamp only; no other pipeline behaviour is touched by this trigger.

begin;

create or replace function security.layer2_discovery_terminal_timestamp_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','pipeline'
as $function$
begin
  if new.job_type='layer2_discovery'
     and new.status in ('completed','failed','cancelled','blocked','succeeded','success')
     and new.completed_at is null
  then
    new.completed_at:=clock_timestamp();
  end if;
  return new;
end
$function$;

drop trigger if exists layer2_discovery_terminal_timestamp_v1 on pipeline.jobs;
create trigger layer2_discovery_terminal_timestamp_v1
before insert or update of status,completed_at on pipeline.jobs
for each row
when (
  new.job_type='layer2_discovery'
  and new.status in ('completed','failed','cancelled','blocked','succeeded','success')
  and new.completed_at is null
)
execute function security.layer2_discovery_terminal_timestamp_v1();

commit;
