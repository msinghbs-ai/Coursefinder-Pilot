-- Stand-ins for the cdesc-admit-outside-record fixture (scratch PostgreSQL 16 only). The trigger function and the settle are the LIVE text (live/); everything below is a stand-in and says so.
\set ON_ERROR_STOP 1
do $r$ declare n text; begin foreach n in array array['anon', 'authenticated', 'service_role'] loop if not exists (select 1 from pg_roles where rolname = n) then execute format('create role %I nologin', n); end if; end loop; end $r$; -- the Supabase API roles the migration revokes from
create schema if not exists security;
create schema if not exists pipeline;
-- settings, as live: the trigger and the settle read them through security.pipeline_num_v1 (stand-in with the same signature and meaning)
create table pipeline.platform_toolset_settings(toolset_key text not null, key text not null, value jsonb, primary key (toolset_key, key));
insert into pipeline.platform_toolset_settings values ('pipeline', 'enrich.course_description_machine_on', '1'), ('pipeline', 'enrich.course_text_items_per_day', '2000');
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$
  select coalesce((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = p_key), p_default) $$;
-- the readings (the columns the trigger reads) and the trigger exactly as live (after update of state, to review, field description)
create table pipeline.field_enrich_items(id bigserial primary key, field text not null, state text not null, value jsonb not null default '{}'::jsonb);
-- the waiting first descriptions and the machine ledger (the columns the settle reads)
create table pipeline.layer4_review_items(id uuid primary key, entity_type text not null, field_code text not null, status text not null, created_at timestamptz not null default now());
create table pipeline.course_description_machine_admissions(id bigserial primary key, review_item_id uuid, outcome text, policy_stamp text, retry_after timestamptz);
create function security.course_description_machine_policy_stamp_v1() returns text language sql stable as $$ select 'stamp-1'::text $$;
-- the admission (stand-in): records each call and its via, sleeps fx.admit_ms (the cost of the real check and read-back), then decides as the real rule would for an item that passes
create table security.fx_admit_calls(item uuid, via text, at timestamptz default clock_timestamp());
create function security.course_description_machine_admit_v1(p_item uuid, p_via text default 'settle') returns jsonb language plpgsql as $$
begin
  insert into security.fx_admit_calls(item, via) values (p_item, p_via);
  perform pg_sleep(coalesce(nullif(current_setting('fx.admit_ms', true), ''), '0')::numeric / 1000);
  update pipeline.layer4_review_items set status = 'approved' where id = p_item and status = 'pending';
  return jsonb_build_object('ok', true);
end $$;
