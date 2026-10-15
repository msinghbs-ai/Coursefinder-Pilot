-- CF-247 (15 Oct 2026): bug fix and feature. Platform Admin, 15 Oct 2026 12:55: "Bug/fix: i'm unable to upload Uni Logos or request to find it".
-- Found: (1) the logo in the provider panel was made clickable by a page watcher that only noticed new tables and panels; when the provider's
-- details arrived after the panel opened (a direct link, a slow load) the logo was never made clickable, so no upload reached the server.
-- (2) The old logo finder was retired on 10 Oct (clean-up batch 6); only 49 of 3,091 providers have a logo (Canada none).
-- Decisions (15 Oct 2026, multiple choice): "make it background Job to find and attached + Plus admin to upload by clicking on logo from
-- provider details blade or list editing"; upload is for the Platform Admin (setting).
-- Replaces: the page watcher that made the provider panel logo clickable (src/ProviderLogo.jsx; the logo is now clickable in the screen itself)
-- Retires: public.layer2_provider_asset_fetch_routes() and public.layer2_provider_asset_promotion_context(uuid) (old logo finder, no caller, no job; marked retiring, dropped by paste file after 14 days)
-- 1 Settings (Logos)   2 Table pipeline.provider_logo_finds   3 Functions: capability, request, next, record   4 Job logo-find and catalogue
-- 5 Register: new components; retiring functions.   Nothing dropped or deleted.

-- 1 Settings
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'logo.upload_min_rank', 'Lowest role that can upload or find a logo', 'Role rank: 4 Pipeline Operator, 5 PIM Admin, 6 Platform Admin. Below this the logo is shown but cannot be changed.', 'number', to_jsonb(6), 1, 6, 'role rank', 760, 'Platform Admin 15 Oct 2026: upload by the Platform Admin', 'Logos', 'provider panel, providers list, logo list; edge function provider-asset-upload; public.admin_provider_logo_find_request'),
 ('pipeline', 'batch.logo_find', 'Providers checked for a logo per run', 'Each run reads this many provider home pages and stores the logo it finds (job logo-find, every 10 minutes).', 'number', to_jsonb(12), 1, 40, 'providers', 761, 'Platform Admin 15 Oct 2026: "make it background Job to find and attached"', 'Logos', 'job logo-find (coverage-sweep mode logo_find)'),
 ('pipeline', 'logo.retry_after_days', 'Look again for a logo not found after', 'A provider whose logo was not found is checked again after this many days (a request from the panel checks it at once).', 'number', to_jsonb(30), 1, 365, 'days', 762, 'Waste rules: flag and move on, try again later', 'Logos', 'public.svc_logo_find_next'),
 ('pipeline', 'logo.min_pixels', 'Smallest logo accepted', 'A PNG, JPEG or WebP logo narrower or shorter than this is not used (SVG logos scale).', 'number', to_jsonb(64), 16, 512, 'pixels', 763, 'A logo must stay sharp in the panel and on the website', 'Logos', 'coverage-sweep mode logo_find')
on conflict do nothing;

-- 2 Table
create table pipeline.provider_logo_finds (
  provider_id uuid primary key references catalogue.providers(id) on delete cascade,
  status text not null default 'queued' check (status in ('queued', 'trying', 'found', 'not_found', 'failed', 'skipped_has_logo')),
  reason text,
  method text,
  source_url text,
  page_url text,
  provider_asset_id uuid,
  tries integer not null default 0,
  last_tried_at timestamptz,
  requested_at timestamptz,
  requested_by uuid,
  updated_at timestamptz not null default now()
);
comment on table pipeline.provider_logo_finds is 'Logo finder (CF-247, 15 Oct 2026): one row per provider the background job has checked or a person has asked it to check; what was found, from which page and how, or why not. Layer 2.';
alter table pipeline.provider_logo_finds enable row level security;
create index provider_logo_finds_requested_idx on pipeline.provider_logo_finds (requested_at) where requested_at is not null;

-- 3 Functions
CREATE OR REPLACE FUNCTION security.logo_upload_min_rank_v1()
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select security.pipeline_num_v1('logo.upload_min_rank', 6)::int
$function$;

-- the screens ask once whether the signed-in person may change logos, and how the finder is doing
CREATE OR REPLACE FUNCTION public.admin_provider_logo_capability()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int; v_min int;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_rank := security.current_role_rank(); v_min := security.logo_upload_min_rank_v1();
  return jsonb_build_object('rank', v_rank, 'min_rank', v_min, 'can_upload', v_rank >= v_min,
    'finder', (select jsonb_build_object('checked', count(*) filter (where status not in ('queued', 'trying')),
                                         'found', count(*) filter (where status = 'found'),
                                         'not_found', count(*) filter (where status in ('not_found', 'failed')),
                                         'waiting', count(*) filter (where status in ('queued', 'trying') or requested_at is not null))
                 from pipeline.provider_logo_finds));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_provider_logo_find_request(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < security.logo_upload_min_rank_v1() then raise exception 'your role cannot change logos' using errcode = '42501'; end if;
  if not exists (select 1 from catalogue.providers p where p.id = p_provider_id) then raise exception 'provider not found' using errcode = 'P0002'; end if;
  insert into pipeline.provider_logo_finds(provider_id, status, requested_at, requested_by, updated_at)
  values (p_provider_id, 'queued', now(), auth.uid(), now())
  on conflict (provider_id) do update set status = 'queued', requested_at = now(), requested_by = auth.uid(), updated_at = now();
  return jsonb_build_object('provider_id', p_provider_id, 'queued', true,
    'has_website', exists (select 1 from catalogue.providers p where p.id = p_provider_id and nullif(btrim(p.website), '') is not null));
end $function$;

-- the next providers to check: asked for first, then providers with the most courses; only providers with a website and no logo
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
end $function$;

-- record what the finder found: a logo is attached (approved, primary) only when the provider still has none; a provider with no logo found is flagged
CREATE OR REPLACE FUNCTION public.svc_logo_find_record(p_provider_id uuid, p_status text, p_reason text, p_method text, p_storage_path text, p_mime_type text,
                                                       p_content_hash text, p_width integer, p_height integer, p_source_url text, p_page_url text, p_evidence jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_asset uuid; v_status text := p_status;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_status not in ('found', 'not_found', 'failed') then raise exception 'unknown status %', p_status; end if;
  if p_status = 'found' then
    if p_storage_path is null or p_content_hash is null or p_mime_type not in ('image/svg+xml', 'image/png', 'image/jpeg', 'image/webp') then raise exception 'stored logo required'; end if;
    if exists (select 1 from catalogue.provider_assets a where a.provider_id = p_provider_id and a.is_primary and a.status = 'approved' and a.asset_type in ('logo', 'logo_dark', 'logo_light')) then
      v_status := 'skipped_has_logo';  -- a person added one meanwhile: theirs stays
    else
      insert into catalogue.provider_assets(provider_id, asset_type, source_url, storage_path, mime_type, width, height, content_hash, is_primary, status, observed_at, verified_at, metadata)
      values (p_provider_id, 'logo', p_source_url, p_storage_path, p_mime_type, p_width, p_height, p_content_hash, true, 'approved', now(), now(),
              jsonb_build_object('source_class', 'website_logo_finder', 'method', p_method, 'page_url', p_page_url, 'managed_storage', true, 'change_control_ref', 'CF-CHG-20260915-247') || coalesce(p_evidence, '{}'::jsonb))
      on conflict (provider_id, asset_type, coalesce(content_hash, ''), source_url) do update
        set storage_path = excluded.storage_path, is_primary = true, status = 'approved', verified_at = now(), metadata = catalogue.provider_assets.metadata || excluded.metadata
      returning id into v_asset;
      update pipeline.enrichment_flags set cleared_at = now() where entity = 'provider' and entity_key = p_provider_id::text and field = 'logo' and cleared_at is null;
    end if;
  else
    insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
    values ('provider', p_provider_id::text, p_provider_id, 'logo', 'logo_not_found', coalesce(p_reason, 'no logo on the home page'), 'logo-find')
    on conflict (entity, entity_key, field, reason_code) do update set reason = excluded.reason, flagged_at = now(), cleared_at = null;
  end if;
  update pipeline.provider_logo_finds set status = v_status, reason = p_reason, method = p_method, source_url = p_source_url, page_url = p_page_url,
         provider_asset_id = coalesce(v_asset, provider_asset_id), updated_at = now()
   where provider_id = p_provider_id;
  return jsonb_build_object('provider_id', p_provider_id, 'status', v_status, 'provider_asset_id', v_asset);
end $function$;

revoke execute on function security.logo_upload_min_rank_v1(), public.admin_provider_logo_capability(), public.admin_provider_logo_find_request(uuid),
  public.svc_logo_find_next(integer), public.svc_logo_find_record(uuid, text, text, text, text, text, text, integer, integer, text, text, jsonb) from public, anon;
revoke execute on function security.logo_upload_min_rank_v1(), public.svc_logo_find_next(integer),
  public.svc_logo_find_record(uuid, text, text, text, text, text, text, integer, integer, text, text, jsonb) from authenticated;
grant execute on function public.admin_provider_logo_capability(), public.admin_provider_logo_find_request(uuid) to authenticated;
grant execute on function security.logo_upload_min_rank_v1(), public.svc_logo_find_next(integer),
  public.svc_logo_find_record(uuid, text, text, text, text, text, text, integer, integer, text, text, jsonb) to service_role;

-- the upload edge function asks the same question as the screens
CREATE OR REPLACE FUNCTION public.svc_logo_upload_allowed(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(max(r.rank), 0) >= security.logo_upload_min_rank_v1()
    from security.user_roles ur join security.roles r on r.code = ur.role_code
   where ur.user_id = p_user_id and (ur.expires_at is null or ur.expires_at > now()) and r.status = 'active'
$function$;
revoke execute on function public.svc_logo_upload_allowed(uuid) from public, anon, authenticated;
grant execute on function public.svc_logo_upload_allowed(uuid) to service_role;

-- 4 Job
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('logo-find', 'Layer 2 reading', 136, 'Logo finder: provider logos from their own websites',
  'Every 10 minutes: reads the home page of providers with a website and no logo (asked-for providers first, then those with the most courses), takes the site''s own logo (the logo image in the page header, the logo the page declares, or its large icon), checks its type and size, stores it and attaches it. A logo a person added is never replaced. Not found is flagged and tried again later (Pipeline settings › Logos).', 6, true)
on conflict (jobname) do nothing;
select cron.schedule('logo-find', '*/10 * * * *', 'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''logo_find'', ''limit'', security.pipeline_num_v1(''batch.logo_find'', 12)::int))');

-- 5 Register
insert into pipeline.component_register(kind, name, layer, purpose, status, replaced_by, retire_after, introduced_in) values
 ('function', 'public.layer2_provider_asset_fetch_routes()', 'L2 read', 'Old logo finder (retired 10 Oct 2026); no caller, no job', 'retiring', 'job logo-find (coverage-sweep mode logo_find)', current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int, '20261015050000 (marked retiring)'),
 ('function', 'public.layer2_provider_asset_promotion_context(uuid)', 'L2 read', 'Old logo finder (retired 10 Oct 2026); no caller, no job', 'retiring', 'public.svc_logo_find_record', current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int, '20261015050000 (marked retiring)'),
 ('job', 'logo-find', 'L2 read', 'Provider logos from their own websites, attached when the provider has none', 'active', null, null, '20261015050000'),
 ('table', 'pipeline.provider_logo_finds', 'L2 read', 'What the logo finder found for each provider, or why not', 'active', null, null, '20261015050000')
on conflict (kind, name) do update set status = excluded.status, purpose = excluded.purpose, replaced_by = excluded.replaced_by, retire_after = excluded.retire_after, introduced_in = excluded.introduced_in, updated_at = now();
