begin;

create or replace function security.admin_provider_identity_quality_summary()
returns jsonb language plpgsql stable security definer set search_path='pg_catalog','catalogue','ref','security','auth' as $$
declare v_rank integer:=0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  return (select jsonb_build_object(
    'providers',count(*),
    'missing_canonical_name',count(*) filter(where canonical_name is null or btrim(canonical_name)=''),
    'missing_display_name',count(*) filter(where display_name is null or btrim(display_name)=''),
    'generic_name_placeholder',count(*) filter(where lower(btrim(coalesce(display_name,canonical_name,''))) in ('location','campus','city','state','region','country','provider','university')),
    'institution_like_city',count(*) filter(where nullif(primary_city,'') is not null and primary_city ~* '(university|institute|college|school|academy|pty|limited|ltd|education|tafe)'),
    'display_matches_city',count(*) filter(where nullif(primary_city,'') is not null and lower(btrim(coalesce(display_name,'')))=lower(btrim(primary_city))),
    'canonical_matches_city',count(*) filter(where nullif(primary_city,'') is not null and lower(btrim(coalesce(canonical_name,'')))=lower(btrim(primary_city))),
    'display_matches_subdivision',count(*) filter(where exists(select 1 from ref.subdivisions s where lower(btrim(s.name))=lower(btrim(coalesce(display_name,''))))),
    'canonical_matches_subdivision',count(*) filter(where exists(select 1 from ref.subdivisions s where lower(btrim(s.name))=lower(btrim(coalesce(canonical_name,''))))),
    'display_matches_country',count(*) filter(where exists(select 1 from ref.countries c where lower(btrim(c.name))=lower(btrim(coalesce(display_name,''))) or lower(btrim(c.iso_alpha2::text))=lower(btrim(coalesce(display_name,''))))),
    'canonical_matches_country',count(*) filter(where exists(select 1 from ref.countries c where lower(btrim(c.name))=lower(btrim(coalesce(canonical_name,''))) or lower(btrim(c.iso_alpha2::text))=lower(btrim(coalesce(canonical_name,''))))),
    'display_differs_from_canonical',count(*) filter(where nullif(btrim(display_name),'') is not null and lower(btrim(display_name))<>lower(btrim(canonical_name)))
  ) from catalogue.providers);
end
$$;
revoke all on function security.admin_provider_identity_quality_summary() from public,anon;
grant execute on function security.admin_provider_identity_quality_summary() to authenticated;

create or replace function public.provider_identity_quality_summary()
returns jsonb language sql stable security invoker set search_path='pg_catalog','security','public' as $$
  select security.admin_provider_identity_quality_summary()
$$;
revoke all on function public.provider_identity_quality_summary() from public,anon;
grant execute on function public.provider_identity_quality_summary() to authenticated;

commit;
