CREATE OR REPLACE FUNCTION public.svc_logo_find_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_items jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select p.id, p.canonical_name, p.website, k.iso_alpha2 country, f.requested_at
      from catalogue.providers p
      left join ref.countries k on k.id = p.country_id
      left join pipeline.provider_logo_finds f on f.provider_id = p.id
     where p.lifecycle_status = 'active' and nullif(btrim(p.website), '') is not null
       and not exists (select 1 from catalogue.provider_assets a where a.provider_id = p.id and a.is_primary and a.status = 'approved'
                        and a.asset_type in ('logo', 'logo_dark', 'logo_light'))
       and (f.provider_id is null
            or f.requested_at is not null
            or f.status = 'queued'
            or (f.status = 'trying' and f.last_tried_at < now() - interval '15 minutes')  -- fixed: claim lease, a run that died
            or (f.status in ('not_found', 'failed') and f.last_tried_at < now() - make_interval(days => security.pipeline_num_v1('logo.retry_after_days', 30)::int)))
     order by (f.requested_at is not null) desc, f.requested_at, (select count(*) from catalogue.courses c where c.provider_id = p.id) desc, p.id
     limit greatest(p_limit, 0)
     for update of p skip locked),
  claim as (
    insert into pipeline.provider_logo_finds(provider_id, status, tries, last_tried_at, updated_at)
    select id, 'trying', 1, now(), now() from pick
    on conflict (provider_id) do update set status = 'trying', tries = pipeline.provider_logo_finds.tries + 1, last_tried_at = now(), requested_at = null, updated_at = now()
    returning provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', pick.id, 'name', pick.canonical_name, 'website', pick.website, 'country', pick.country)), '[]'::jsonb)
    into v_items from pick join claim on claim.provider_id = pick.id;
  return jsonb_build_object('items', v_items, 'min_pixels', security.pipeline_num_v1('logo.min_pixels', 64)::int);
end $function$
