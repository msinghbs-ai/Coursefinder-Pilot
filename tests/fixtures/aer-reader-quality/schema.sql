-- CF-247 AER reader quality: the live shapes the migration touches (read from project fxcwkweaxjtknorudmwp on 8 Nov 2026, columns, defaults,
-- NOT NULL and constraints as live), the live svc_worker_settings_v1, and the live settings next to the new keys. Isolated PostgreSQL only.
create schema if not exists pipeline; create schema if not exists auth;
create or replace function auth.role() returns text language sql as $$ select 'service_role'::text $$;
create table pipeline.platform_toolsets (
  key text primary key, label text not null, kind text not null, layers integer[] not null default '{}', provider_key text, enforcement text,
  help text not null default '', sort integer not null default 100, reason text, updated_by uuid, updated_at timestamptz not null default now());
create table pipeline.platform_toolset_settings (
  toolset_key text not null references pipeline.platform_toolsets(key), key text not null, label text not null, help text not null default '',
  kind text not null, value jsonb not null, min_value numeric, max_value numeric, unit text, sort integer not null default 100, reason text,
  updated_by uuid, updated_at timestamptz not null default now(), section text not null default 'Notices', used_by text,
  constraint platform_toolset_settings_kind_check check (kind = any (array['number','text','boolean','list'])),
  primary key (toolset_key, key));
insert into pipeline.platform_toolsets(key, label, kind) values ('pipeline', 'Pipeline (job sizes, re-reads and retries)', 'platform'), ('firecrawl', 'Firecrawl', 'provider');
-- live neighbours, with their live values and ranges
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, min_value, max_value, unit, sort, section, used_by) values
 ('pipeline', 'enrich.course_entry_slice_overlap_chars', 'Course entry requirements: overlap between slices', 'number', '600', 0, 4000, 'characters', 919, 'Entry requirements', 'worker coverage-sweep enrich_ai (entry_requirements)'),
 ('pipeline', 'reading.entry_range_lower_bound_on', 'Entry reader: range lower bound', 'number', '0', 0, 1, 'on/off', 1126, 'Entry requirements', 'worker'),
 ('pipeline', 'reading.entry_global_pages_on', 'Entry reader: read global-qualification pages', 'number', '0', 0, 1, 'on/off', 1128, 'Entry requirements', 'worker'),
 ('pipeline', 'reading.entry_global_qualifications', 'Entry reader: global qualifications', 'list', '["international baccalaureate", "ib diploma", "global assessment certificate", "gac"]', null, null, 'qualifications', 1129, 'Entry requirements', 'worker'),
 ('pipeline', 'batch.coverage_read', 'A job size outside the worker keys', 'number', '60', 1, 200, 'items', 100, 'Jobs', 'job'),
 ('firecrawl', 'read_proxy', 'Firecrawl proxy', 'text', '"basic"', null, null, null, 10, 'Firecrawl', 'worker');
create schema if not exists public;
CREATE OR REPLACE FUNCTION public.svc_worker_settings_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return (select coalesce(jsonb_object_agg(s.key, s.value), '{}'::jsonb) from pipeline.platform_toolset_settings s
           where (s.toolset_key = 'firecrawl' and s.key in ('read_proxy', 'map_limit_course_site', 'map_limit_central', 'map_limit_central_search', 'map_limit_scholarships',
                                                          'search_results_website', 'search_results_register', 'search_results_cricos',
                                                          'search_results_scholarship_search', 'search_results_scholarship_discover'))
              or (s.toolset_key = 'pipeline' and (s.key like 'enrich.%' or s.key like 'reading.%'))  -- v2.15.275: Enrich fields worker values
              or (s.toolset_key = 'pipeline' and s.key like 'scholarship.%'));  -- CF-247 scholarship recovery F10: scholarship worker sizes and waits
end $function$;
