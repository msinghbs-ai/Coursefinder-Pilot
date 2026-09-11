begin;

create or replace function security.scheduler_workflow_route_gap_count_v1(
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid default null
) returns integer
language sql
stable
security definer
set search_path=''
as $function$
  select count(*)::integer
  from (
    select distinct sc.profile_id
    from public.layer2_scope_courses(upper(p_country_code),lower(p_scope_type),p_scope_id) sc
    where not exists (
      select 1
      from pipeline.layer2_profile_provider_routes r
      join pipeline.layer2_acquisition_providers ap on ap.id=r.acquisition_provider_id
      left join vault.decrypted_secrets ds on ds.id=ap.vault_secret_id
      where r.profile_id=sc.profile_id
        and r.enabled=true
        and ap.enabled=true
        and lower(coalesce(ap.provider_key,''))<>'parsebot'
        and (
          lower(coalesce(ap.auth_scheme,'none'))='none'
          or nullif(ds.decrypted_secret,'') is not null
        )
    )
  ) gaps
$function$;
revoke all on function security.scheduler_workflow_route_gap_count_v1(text,text,uuid) from public,anon,authenticated;

commit;
