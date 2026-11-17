-- CF-247 Layer 1 register apply: records per database call is a setting (Platform Admin 17 Nov 2026 14:30, S2-Build lane).
-- Cause: applying the CRICOS register edition of 11 Nov 2026 (run d35d2541, 1,953 courses) failed at 0 of 1,953 with
--   "svc_layer1_apply_register_records: canceling statement due to statement timeout" five times. The service role runs under the API's
--   8-second statement limit (role authenticator), and layer1-au-depth sent 250 records per call, a size written into its code. A limit set
--   inside the function cannot lift the limit of the statement already running, so the fix is smaller calls: the number of records per call
--   is now the setting layer1.register_apply_chunk (50), read by layer1-au-depth v1.9.0 and layer1-nz-live v1.4.0 (the NZQA run of
--   13 Nov 2026 failed the same way).
-- Replaces: the fixed 250 records per svc_layer1_apply_register_records call in layer1-au-depth and layer1-nz-live (G2).
-- Retires: nothing.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'layer1.register_apply_chunk', 'Layer 1 register: records per apply call',
  'How many register records (providers and courses) one call of the register apply function takes. Each call must finish within the database''s 8-second limit for the service; lower it if an apply stops with a statement timeout.',
  'number', to_jsonb(50), 10, 250, 'records', 1201, 'CRICOS 11 Nov 2026 edition apply timed out at 250 records per call (Platform Admin 17 Nov 2026 14:30)', 'Layer 1 register',
  'layer1-au-depth and layer1-nz-live (svc_layer1_apply_register_records)')
on conflict (toolset_key, key) do nothing;

create or replace function public.svc_layer1_register_settings_v1()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return (select coalesce(jsonb_object_agg(s.key, s.value), '{}'::jsonb) from pipeline.platform_toolset_settings s
           where s.toolset_key = 'pipeline' and s.key like 'layer1.%');
end $function$;
comment on function public.svc_layer1_register_settings_v1() is 'Layer 1 register workers (layer1-au-depth, layer1-nz-live): the pipeline settings named layer1.*, read at the start of each request (G2).';
revoke all on function public.svc_layer1_register_settings_v1() from public, anon, authenticated;
grant execute on function public.svc_layer1_register_settings_v1() to service_role;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, introduced_in)
select 'function', 'public.svc_layer1_register_settings_v1', 'Layer 1', 'Layer 1 register', 'Gives the Layer 1 register workers their layer1.* settings (records per apply call).', 'active', '20261117150000'
where not exists (select 1 from pipeline.component_register where kind = 'function' and name = 'public.svc_layer1_register_settings_v1');

do $$
begin
  if (select (value #>> '{}')::int from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'layer1.register_apply_chunk') is null then
    raise exception 'post-check: layer1.register_apply_chunk missing';
  end if;
  if not ((select public.svc_layer1_register_settings_v1()) ? 'layer1.register_apply_chunk') then raise exception 'post-check: settings reader'; end if;
end $$;
