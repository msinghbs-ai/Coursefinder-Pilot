create table security.roles (
  code text primary key,
  name text not null,
  rank smallint not null unique,
  description text,
  status text not null default 'active'
);

insert into security.roles(code,name,rank,description) values
('viewer','Viewer',1,'Read-only catalogue/PIM access'),
('counsellor','Counsellor',2,'Counsellor/search and recommendation access'),
('curator','Curator',3,'Catalogue curation and Layer 4 review'),
('pipeline_operator','Pipeline Operator',4,'Pipeline execution and operational controls'),
('pim_admin','PIM Admin',5,'PIM configuration and catalogue administration'),
('platform_admin','Platform Admin',6,'Full application administration')
on conflict (code) do nothing;

create table security.user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role_code text not null references security.roles(code),
  granted_at timestamptz not null default now(),
  granted_by uuid references auth.users(id),
  expires_at timestamptz,
  primary key(user_id,role_code)
);
create index user_roles_role_idx on security.user_roles(role_code);

create table security.service_permissions (
  service_name text not null,
  permission_code text not null,
  minimum_role_code text references security.roles(code),
  description text,
  primary key(service_name,permission_code)
);

alter table security.roles enable row level security;
alter table security.user_roles enable row level security;
alter table security.service_permissions enable row level security;

revoke all on all tables in schema security from anon, authenticated;
revoke usage on schema security from anon, authenticated;

grant usage on schema security to service_role;
grant all on all tables in schema security to service_role;
