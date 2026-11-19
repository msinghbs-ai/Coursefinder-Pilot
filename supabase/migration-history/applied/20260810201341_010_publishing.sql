create table publishing.channels (
  code text primary key,
  name text not null,
  audience text not null,
  status text not null default 'active',
  config jsonb not null default '{}'::jsonb
);

insert into publishing.channels(code,name,audience) values
('website','Website','public'),
('zoho','Zoho Creator','internal'),
('admin','Admin','internal')
on conflict (code) do nothing;

create table publishing.entity_states (
  entity_id uuid not null references pim.entity_registry(id) on delete cascade,
  channel_code text not null references publishing.channels(code),
  locale text not null default 'en',
  publication_status text not null default 'unpublished',
  published_at timestamptz,
  unpublished_at timestamptz,
  completeness_score numeric(5,2),
  last_checked_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key(entity_id,channel_code,locale)
);
create index publishing_entity_states_status_idx on publishing.entity_states(channel_code,publication_status);

revoke all on all tables in schema publishing from anon, authenticated;
revoke usage on schema publishing from anon, authenticated;
grant usage on schema publishing to service_role;
grant all on all tables in schema publishing to service_role;
