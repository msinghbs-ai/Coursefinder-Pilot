-- CF-247 probe: the Settings write function's shell (body filled in the next migration).
create or replace function public.admin_pipeline_settings_write(p_key text, p_value jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $f$
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  raise exception 'unknown setting %', p_key;
end $f$;
revoke all on function public.admin_pipeline_settings_write(text, jsonb) from public, anon;
grant execute on function public.admin_pipeline_settings_write(text, jsonb) to authenticated;
