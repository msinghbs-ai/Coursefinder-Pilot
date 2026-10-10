begin;
revoke all on function public.provider_identity_quality_summary() from public, anon, authenticated;
grant execute on function public.provider_identity_quality_summary() to service_role;
commit;
