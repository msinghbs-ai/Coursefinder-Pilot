-- Extra objects that 20261117040000_cf247_rm_destination_schema_pack.sql builds on (fixtures only, never a Supabase project).
create schema if not exists auth;
create table security.user_access_events (id uuid primary key default gen_random_uuid(), actor_user_id uuid, target_user_id uuid, action text not null,
  constraint user_access_events_action_check check (action = any (array['user_created', 'user_invited', 'roles_replaced', 'user_disabled', 'user_enabled'])));
create table pipeline.platform_toolset_settings (toolset_key text not null, key text not null, label text not null, help text not null, kind text not null, value jsonb not null,
  min_value numeric, max_value numeric, unit text, sort int not null, reason text, section text not null, used_by text, primary key (toolset_key, key));
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default) $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('fixture.uid', true), '')::uuid $$;
create function security.current_role_rank() returns int language sql stable as $$ select nullif(current_setting('fixture.rank', true), '')::int $$;
