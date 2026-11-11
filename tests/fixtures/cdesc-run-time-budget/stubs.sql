-- Stand-ins for the cdesc-run-time-budget fixture (scratch PostgreSQL only). The settle and the consumer read-back are the LIVE text (live/); everything below is a stand-in with the columns they read.
\set ON_ERROR_STOP 1
do $r$ declare n text; begin foreach n in array array['anon', 'authenticated', 'service_role'] loop if not exists (select 1 from pg_roles where rolname = n) then execute format('create role %I nologin', n); end if; end loop; end $r$;
create schema if not exists security; create schema if not exists pipeline; create schema if not exists catalogue;
create table pipeline.platform_toolset_settings(toolset_key text not null, key text not null, value jsonb, primary key (toolset_key, key));
insert into pipeline.platform_toolset_settings values ('pipeline', 'enrich.course_description_machine_on', '1'), ('pipeline', 'enrich.course_text_items_per_day', '2000'), ('pipeline', 'gaps.recheck_days', '60');
create function security.pipeline_num_v1(p_key text, p_default numeric) returns numeric language sql stable as $$
  select coalesce((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = p_key), p_default) $$;
create function security.course_description_machine_policy_stamp_v1() returns text language sql stable as $$ select 'stamp-1'::text $$;
create table catalogue.courses(id uuid primary key, stable_key text);
create table pipeline.layer4_review_items(id uuid primary key, entity_type text, field_code text, status text, created_at timestamptz default now());
create table pipeline.course_description_machine_admissions(id bigserial primary key, review_item_id uuid, course_id uuid, outcome text, policy_stamp text, retry_after timestamptz,
  after_description text, withdrawn_at timestamptz, consumer_check text, consumer_checked_at timestamptz);
-- the admission (stand-in): one second each (the measured worst case of a real check and read-back is about 5 s), then approves
create function security.course_description_machine_admit_v1(p_item uuid, p_via text default 'settle') returns jsonb language plpgsql as $$
begin perform pg_sleep(1); update pipeline.layer4_review_items set status = 'approved' where id = p_item; return jsonb_build_object('ok', true); end $$;
-- the Website read-back (stand-in): half a second each, shows the admitted text
create function public.website_v2_course(p_key text) returns jsonb language plpgsql as $$
begin perform pg_sleep(0.5); return jsonb_build_object('item', jsonb_build_object('description', 'text ' || p_key)); end $$;
-- the job's earlier steps (stand-in): the statement has already run p_secs seconds when the step starts, as in security.course_description_machine_run_v1
create function security.fx_settle_after(p_secs numeric) returns jsonb language plpgsql as $$ begin perform pg_sleep(p_secs); return security.course_description_machine_settle_v1(); end $$;
create function security.fx_recheck_after(p_secs numeric) returns jsonb language plpgsql as $$ begin perform pg_sleep(p_secs); return security.course_description_machine_consumer_recheck_v1(); end $$;
