create table if not exists pipeline.pilot_edge_execution_queue(
 id uuid primary key default extensions.gen_random_uuid(),
 function_name text not null,
 body jsonb not null default '{}'::jsonb,
 status text not null default 'queued' check(status in ('queued','submitted','failed')),
 net_request_id bigint,
 error_text text,
 created_at timestamptz not null default now(),
 submitted_at timestamptz
);
alter table pipeline.pilot_edge_execution_queue enable row level security;
revoke all on pipeline.pilot_edge_execution_queue from public,anon,authenticated;
grant select,insert,update on pipeline.pilot_edge_execution_queue to service_role;

create or replace function pipeline.trg_submit_pilot_edge_execution()
returns trigger
language plpgsql
security definer
set search_path=pipeline,public
as $$
begin
  if new.function_name not in ('layer1-ca-on-college-programs','layer1-ca-algonquin-catalogue') then
    new.status:='failed';
    new.error_text:='function not allowlisted';
    return new;
  end if;
  begin
    new.net_request_id:=pipeline.svc_pilot_invoke_edge(new.function_name,new.body);
    new.status:='submitted';
    new.submitted_at:=now();
  exception when others then
    new.status:='failed';
    new.error_text:=sqlerrm;
  end;
  return new;
end $$;

drop trigger if exists submit_pilot_edge_execution on pipeline.pilot_edge_execution_queue;
create trigger submit_pilot_edge_execution before insert on pipeline.pilot_edge_execution_queue
for each row execute function pipeline.trg_submit_pilot_edge_execution();