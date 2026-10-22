-- CF-247 (22 Oct 2026). Platform Admin 19:05: "Yes, we need to accommodate manual actions as well. Do what complete the process in manual
-- mode" (Adapter builder back in the Layer 2/3 tabs, Open in builder from Build adapter, screenshots kept while a build is open).
-- Adapter builder screenshots were removed after retention.screenshot_keep_days (7) even while a person was still building that
-- university's adapter by hand. A university's latest capture is now kept while its adapter is not admitting, up to
-- retention.screenshot_open_build_days (30: the screenshot links the builder shows last 30 days).
-- Replaces: public.svc_retention_files_next and security.retention_estimate_v1 (adapter screenshots of an open build kept). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'retention.screenshot_open_build_days', 'Keep screenshots of an open build for', 'Adapter builder screenshots of a university''s latest capture are kept while its adapter is not admitting yet, up to this many days (the links to them last 30 days).', 'number', to_jsonb(30), 7, 30, 'days', 744, 'CF-247 22 Oct 2026 (Platform Admin 19:05, manual mode)', 'Housekeeping', 'public.svc_retention_files_next; security.retention_estimate_v1')
on conflict (toolset_key, key) do nothing;

create or replace function security.screenshot_in_open_build_v1(p_name text, p_created timestamptz) returns boolean
language sql stable security definer set search_path = '' as $function$
  -- an adapter-captures file <provider>/<draft>/<n>.png of the provider's latest draft, while its adapter is not admitting, within the days
  select p_created > now() - make_interval(days => security.pipeline_num_v1('retention.screenshot_open_build_days', 30)::int)
     and split_part(p_name, '/', 1) ~ '^[0-9a-f-]{36}$' and split_part(p_name, '/', 2) ~ '^[0-9a-f-]{36}$'
     and split_part(p_name, '/', 2) = (select d.id::text from pipeline.uni_adapter_drafts d where d.provider_id = split_part(p_name, '/', 1)::uuid order by d.created_at desc limit 1)
     and security.provider_adapter_status_v1(split_part(p_name, '/', 1)::uuid) <> 'admitting'
$function$;
comment on function security.screenshot_in_open_build_v1(text, timestamptz) is 'CF-247 22 Oct 2026: an Adapter builder screenshot of a build still open (latest capture, adapter not admitting, within retention.screenshot_open_build_days); kept by Storage & retention.';
revoke all on function security.screenshot_in_open_build_v1(text, timestamptz) from public;

do $edit$
declare v_def text; v_old text; v_n int;
begin
  v_def := pg_get_functiondef('public.svc_retention_files_next(uuid,integer)'::regprocedure);
  if md5(v_def) <> '44fe53e8d1a4e92b88c8cbee102d3402' then raise exception 'live public.svc_retention_files_next differs from the definition this change edits'; end if;
  v_old := $o$where bucket_id = 'adapter-captures' and created_at < now() - make_interval(days => security.pipeline_num_v1('retention.screenshot_keep_days', 7)::int)$o$;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'files_next: screenshot rule must occur once'; end if;
  execute replace(v_def, v_old, v_old || ' and not security.screenshot_in_open_build_v1(name, created_at)');

  v_def := pg_get_functiondef('security.retention_estimate_v1(text)'::regprocedure);
  if md5(v_def) <> 'dadfaab10eb03a0407e20625388f6489' then raise exception 'live security.retention_estimate_v1 differs from the definition this change edits'; end if;
  v_old := $o$filter (where o.created_at < now() - make_interval(days => security.pipeline_num_v1('retention.screenshot_keep_days', 7)::int))$o$;
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_n not in (1, 2) then raise exception 'estimate: screenshot rule found % times', v_n; end if;
  execute replace(v_def, v_old, $n$filter (where o.created_at < now() - make_interval(days => security.pipeline_num_v1('retention.screenshot_keep_days', 7)::int) and not security.screenshot_in_open_build_v1(o.name, o.created_at))$n$);
end $edit$;

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.screenshot_in_open_build_v1', 'Housekeeping', 'Adapter builder screenshot of a build still open (kept)', 'active', '{}', '20261022031000')
on conflict (kind, name) do nothing;
