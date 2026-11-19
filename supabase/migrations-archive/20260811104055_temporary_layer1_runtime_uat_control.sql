create table if not exists pipeline.layer1_runtime_uat_control (
  id boolean primary key default true check (id),
  token text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
revoke all on pipeline.layer1_runtime_uat_control from anon, authenticated;
grant select on pipeline.layer1_runtime_uat_control to service_role;
insert into pipeline.layer1_runtime_uat_control(id, token, active)
values (true, encode(extensions.gen_random_bytes(32), 'hex'), true)
on conflict (id) do update set token=excluded.token, active=true, created_at=now();
