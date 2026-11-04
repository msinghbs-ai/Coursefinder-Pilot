-- Run now fixtures: what migration 20261104610000 needs beyond the intake-dates fixture database (CF-247, Platform Admin 4 Nov 2026 20:05).
-- Scratch PostgreSQL only (never a Supabase project): see run.sh. Nothing here is a copy of live data. Column names as live (read 4 Nov 2026 20:09).
-- the task tables (pipeline.admin_jobs as live: the intake-dates stub has five columns only)
alter table pipeline.admin_jobs add column if not exists kind text, add column if not exists lane text, add column if not exists state text, add column if not exists title text,
  add column if not exists cursor jsonb not null default '{}', add column if not exists error text, add column if not exists cancel_requested boolean not null default false,
  add column if not exists pause_requested boolean not null default false, add column if not exists requested_by uuid, add column if not exists reason text,
  add column if not exists created_at timestamptz not null default now(), add column if not exists started_at timestamptz, add column if not exists finished_at timestamptz,
  add column if not exists scope text, add column if not exists outcome text, add column if not exists outcome_detail jsonb;
alter table pipeline.admin_jobs alter column requested_by set not null, alter column kind set not null, alter column state set not null, alter column reason set not null;
create table if not exists pipeline.admin_job_kinds(kind text primary key, label text not null, what text not null default '', can_pause boolean not null default false,
  added_at timestamptz not null default now(), added_in text not null default '');
create table if not exists pipeline.admin_control_events(id bigserial primary key, area text not null, action text not null, target text, detail jsonb not null, actor uuid,
  created_at timestamptz not null default now());
create table if not exists pipeline.edge_request_log(slot int, request_id bigint, function_name text, mode text, created_at timestamptz default now());
-- roles (security.current_role_rank as live, md5 read 4 Nov 2026)
create table if not exists security.roles(code text primary key, rank smallint not null, status text not null default 'active');
create table if not exists security.user_roles(user_id uuid, role_code text references security.roles(code), expires_at timestamptz);
create or replace function auth.uid() returns uuid language sql stable as $f$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $f$;
CREATE OR REPLACE FUNCTION security.current_role_rank()
 RETURNS smallint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'security', 'auth'
AS $function$
select coalesce(max(r.rank),0)::smallint
from security.user_roles ur join security.roles r on r.code=ur.role_code
where ur.user_id=auth.uid() and (ur.expires_at is null or ur.expires_at>now()) and r.status='active'
$function$;
-- the consumer read-back: api.website_v2_course_item's intakes[] (the live expression, as the intake-dates fixture uses it); Zoho not answering here
create or replace function api.website_v2_course_item(p_course_id uuid, p_cities text[] default null, p_postcodes text[] default null) returns jsonb language sql stable as $f$
  select jsonb_build_object('id', d.course_id, 'intakes', coalesce((select jsonb_agg(distinct jsonb_build_object('label', i->>'label', 'month', api.website_v2_label_month(i->>'label'), 'year', i->'year',
                  'start_date', i->'start_date', 'application_deadline', i->'application_deadline'))
                 from jsonb_array_elements(coalesce(d.intake_options,'[]'::jsonb)) i where nullif(i->>'label','') is not null), '[]'::jsonb))
    from search.course_documents d where d.course_id = p_course_id $f$;
create or replace function public.zoho_edge_course_lookup_v1(p_identifier text) returns jsonb language plpgsql as $f$ begin raise exception 'fixture: Zoho not connected'; end $f$;

-- Authoritative admin_jobs progress default/nullability (production pg_attribute, 4 Nov 2026).
alter table pipeline.admin_jobs alter column progress set default '{}'::jsonb, alter column progress set not null;
