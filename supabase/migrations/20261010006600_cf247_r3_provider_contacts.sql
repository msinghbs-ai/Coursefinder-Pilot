-- CF-247 v2.15.234 (R3): Platform Admin bug list of 10 Oct 2026 — Fix 2 (phone and email). Decisions: "Both, kept separate",
-- "Fill automatically", CRICOS contacts "All at once".
--  1. pipeline.provider_contact_points (where each contact came from) and pipeline.provider_contact_checks (when each provider was read).
--  2. Worker functions for coverage-sweep v0.17.33: contact_page reads the provider's own home and contact pages for its public phone
--     and email and fills catalogue.providers.phone/email only when empty (a value entered by hand is never replaced); cricos_peo reads
--     the Principal Executive Officer from the CRICOS website and holds it as an internal regulatory contact, never published.
--  3. admin_provider_edit_read returns where the public contact came from and, for PIM Operators and above, the regulatory contact.
--  4. Two schedules, registered in the automation catalogue (pause, frequency and batch size in the admin).
-- No consumer API reads these tables. md5-checked before and after. Nothing is dropped or deleted.
do $guard$
declare v_expected jsonb := jsonb_build_object('public.admin_provider_edit_read(uuid)', 'fd6fec4d444de5eb920b8a618e1a7d09');
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 1. Where each contact came from. public_general = the provider's own site (copied into catalogue.providers.phone/email when empty);
--    regulatory_peo = the Principal Executive Officer on the CRICOS website, held for internal use and never published.
create table if not exists pipeline.provider_contact_points (
  id bigint generated always as identity primary key,
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  kind text not null check (kind in ('public_general', 'regulatory_peo')),
  source text not null check (source in ('provider_site', 'cricos', 'manual')),
  name text, title text, phone text, email text, source_url text,
  evidence jsonb not null default '{}'::jsonb,
  observed_at timestamptz not null default now(),
  is_current boolean not null default true);
create unique index if not exists provider_contact_points_current on pipeline.provider_contact_points(provider_id, kind) where is_current;
alter table pipeline.provider_contact_points enable row level security;
revoke all on pipeline.provider_contact_points from anon, authenticated;

create table if not exists pipeline.provider_contact_checks (
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  kind text not null check (kind in ('public_general', 'regulatory_peo')),
  checked_at timestamptz not null default now(),
  outcome text not null,
  evidence jsonb not null default '{}'::jsonb,
  primary key (provider_id, kind));
alter table pipeline.provider_contact_checks enable row level security;
revoke all on pipeline.provider_contact_checks from anon, authenticated;

-- 2. Worker functions (service role only).
create or replace function public.svc_provider_contact_next(p_limit integer) returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select p.id, coalesce(p.display_name, p.canonical_name) name, p.website, security.coverage_country(p.id) country
      from catalogue.providers p
     where p.lifecycle_status = 'active' and p.website ~* '^https?://' and (p.phone is null or p.email is null)
       and not security.third_party_host_v1(p.website)
       and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
       and not exists (select 1 from pipeline.provider_contact_checks k where k.provider_id = p.id and k.kind = 'public_general' and k.checked_at > now() - interval '90 days')
     order by (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') desc
     limit greatest(1, least(coalesce(p_limit, 8), 20))),
  lease as (insert into pipeline.provider_contact_checks(provider_id, kind, checked_at, outcome) select id, 'public_general', now(), 'leased' from pick
            on conflict (provider_id, kind) do update set checked_at = now(), outcome = 'leased' returning provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', p.id, 'name', p.name, 'website', p.website, 'country', p.country)), '[]'::jsonb) into v
    from pick p where p.id in (select provider_id from lease);
  return v;
end $f$;

create or replace function public.svc_provider_contact_record(p_provider_id uuid, p_phone text, p_email text, p_url text, p_evidence jsonb) returns void language plpgsql security definer set search_path to '' as $f$
declare v_phone text := nullif(btrim(coalesce(p_phone, '')), ''); v_email text := lower(nullif(btrim(coalesce(p_email, '')), ''));
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then v_email := null; end if;
  if v_phone is not null and length(regexp_replace(v_phone, '\D', '', 'g')) not between 8 and 15 then v_phone := null; end if;
  insert into pipeline.provider_contact_checks(provider_id, kind, checked_at, outcome, evidence)
  values (p_provider_id, 'public_general', now(), case when v_phone is null and v_email is null then 'not_found' else 'found' end, coalesce(p_evidence, '{}'::jsonb))
  on conflict (provider_id, kind) do update set checked_at = now(), outcome = excluded.outcome, evidence = excluded.evidence;
  if v_phone is null and v_email is null then return; end if;
  update pipeline.provider_contact_points set is_current = false where provider_id = p_provider_id and kind = 'public_general' and is_current;
  insert into pipeline.provider_contact_points(provider_id, kind, source, phone, email, source_url, evidence)
  values (p_provider_id, 'public_general', 'provider_site', v_phone, v_email, p_url, coalesce(p_evidence, '{}'::jsonb));
  -- automated: fills only an empty value; a value entered by hand is locked and kept by the manual-value guard
  update catalogue.providers set phone = coalesce(phone, v_phone), email = coalesce(email, v_email), updated_at = now()
   where id = p_provider_id and ((phone is null and v_phone is not null) or (email is null and v_email is not null));
end $f$;

create or replace function public.svc_cricos_peo_next(p_limit integer) returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select p.id, coalesce(p.display_name, p.canonical_name) name,
           (select min(upper(r.registration_code)) from catalogue.provider_registrations r where r.provider_id = p.id and lower(r.registration_scheme) = 'cricos') cricos
      from catalogue.providers p
     where p.lifecycle_status = 'active'
       and exists (select 1 from catalogue.provider_registrations r where r.provider_id = p.id and lower(r.registration_scheme) = 'cricos' and r.registration_code ~* '^[0-9]{5}[A-Z]$')
       and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
       and not exists (select 1 from pipeline.provider_contact_checks k where k.provider_id = p.id and k.kind = 'regulatory_peo'
                         and (k.checked_at > now() - interval '180 days' and k.outcome <> 'budget' or k.checked_at > now() - interval '1 hour'))
     order by (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') desc
     limit greatest(1, least(coalesce(p_limit, 4), 8))),
  lease as (insert into pipeline.provider_contact_checks(provider_id, kind, checked_at, outcome) select id, 'regulatory_peo', now(), 'leased' from pick
            on conflict (provider_id, kind) do update set checked_at = now(), outcome = 'leased' returning provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', p.id, 'name', p.name, 'cricos', p.cricos)), '[]'::jsonb) into v
    from pick p where p.id in (select provider_id from lease);
  return v;
end $f$;

create or replace function public.svc_cricos_peo_record(p_provider_id uuid, p_outcome text, p_name text, p_title text, p_phone text, p_email text, p_url text, p_evidence jsonb)
returns void language plpgsql security definer set search_path to '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.provider_contact_checks(provider_id, kind, checked_at, outcome, evidence)
  values (p_provider_id, 'regulatory_peo', now(), coalesce(p_outcome, 'not_found'), coalesce(p_evidence, '{}'::jsonb))
  on conflict (provider_id, kind) do update set checked_at = now(), outcome = excluded.outcome, evidence = excluded.evidence;
  if coalesce(p_outcome, '') <> 'found' or coalesce(nullif(btrim(p_name), ''), nullif(btrim(p_phone), ''), nullif(btrim(p_email), '')) is null then return; end if;
  update pipeline.provider_contact_points set is_current = false where provider_id = p_provider_id and kind = 'regulatory_peo' and is_current;
  insert into pipeline.provider_contact_points(provider_id, kind, source, name, title, phone, email, source_url, evidence)
  values (p_provider_id, 'regulatory_peo', 'cricos', left(nullif(btrim(p_name), ''), 200), left(nullif(btrim(p_title), ''), 200), left(nullif(btrim(p_phone), ''), 40),
          lower(left(nullif(btrim(p_email), ''), 200)), p_url, coalesce(p_evidence, '{}'::jsonb));
end $f$;
revoke all on function public.svc_provider_contact_next(integer), public.svc_provider_contact_record(uuid, text, text, text, jsonb),
  public.svc_cricos_peo_next(integer), public.svc_cricos_peo_record(uuid, text, text, text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_provider_contact_next(integer), public.svc_provider_contact_record(uuid, text, text, text, jsonb),
  public.svc_cricos_peo_next(integer), public.svc_cricos_peo_record(uuid, text, text, text, text, text, text, jsonb) to service_role;

-- 3. Provider read

CREATE OR REPLACE FUNCTION public.admin_provider_edit_read(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  if not exists (select 1 from catalogue.providers where id = p_provider_id) then raise exception 'provider not found'; end if;
  return (select jsonb_build_object(
    'provider', jsonb_build_object('id', p.id, 'canonical_name', p.canonical_name, 'display_name', p.display_name, 'short_name', p.short_name,
               'website', p.website, 'phone', p.phone, 'email', p.email, 'description', p.description, 'primary_city', p.primary_city,
               'address_line1', p.address_line1, 'postcode', p.postcode, 'lifecycle_status', p.lifecycle_status, 'country', k.name, 'state', s.name,
               'manual_provider', p.stable_key like 'manual:%', 'website_verdict', security.provider_site_verdict_v1(p.id, p.website),
               'active_courses', (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')),
    'course_finder', (select jsonb_build_object('address', d.website, 'status', d.status, 'pages_found', d.kept_count, 'mapped_at', d.mapped_at,
                               'verdict', security.provider_site_verdict_v1(p.id, d.website), 'source', d.site_source)
                        from pipeline.coverage_provider_discovery d where d.provider_id = p.id),
    'link_recipe', (select jsonb_build_object('search_domain', r.search_domain, 'patterns', r.patterns, 'active', r.active)
                      from pipeline.course_link_recipes r where r.provider_id = p.id),
    -- v2.15.234 (Fix 2): where the public phone and email came from, and (PIM Operator and above) the regulator's contact, internal only
    'public_contact', (select jsonb_build_object('phone', cp.phone, 'email', cp.email, 'url', cp.source_url, 'at', cp.observed_at)
                         from pipeline.provider_contact_points cp where cp.provider_id = p.id and cp.kind = 'public_general' and cp.is_current),
    'regulatory_contact', case when v_rank >= 5 then (select jsonb_build_object('name', cp.name, 'title', cp.title, 'phone', cp.phone, 'email', cp.email, 'url', cp.source_url, 'at', cp.observed_at)
                         from pipeline.provider_contact_points cp where cp.provider_id = p.id and cp.kind = 'regulatory_peo' and cp.is_current) end,
    'regulatory_check', case when v_rank >= 5 then (select jsonb_build_object('outcome', k.outcome, 'at', k.checked_at) from pipeline.provider_contact_checks k where k.provider_id = p.id and k.kind = 'regulatory_peo') end,
    'locks', (select coalesce(jsonb_object_agg(l.field, jsonb_build_object('mode', l.mode, 'at', l.set_at)), '{}'::jsonb)
               from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('at', h.at, 'field', h.field, 'action', h.action, 'before', h.before, 'after', h.after,
               'reason', h.reason, 'by', u.email) order by h.at desc), '[]'::jsonb)
               from (select * from pipeline.manual_edit_log where entity = 'provider' and entity_id = p.id order by at desc limit 20) h left join auth.users u on u.id = h.actor),
    'can_edit', v_rank >= 3, 'can_manage', v_rank >= 5)
   from catalogue.providers p left join ref.countries k on k.id = p.country_id left join ref.subdivisions s on s.id = p.subdivision_id where p.id = p_provider_id);
end $function$;

-- 4. Schedules. Public contacts: 8 providers every 3 minutes (direct reads). CRICOS contacts: Platform Admin decision "All at once",
--    2 providers a minute until every AU provider with courses is read (Firecrawl, inside the budget reserve).
select cron.schedule('provider-contact-page', '*/3 * * * *', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"contact_page","limit":8}'::jsonb)$c$);
select cron.schedule('cricos-peo', '* * * * *', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"cricos_peo","limit":2}'::jsonb)$c$);
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('provider-contact-page', 'Course pages', 15, 'Find provider phone and email', 'Reads the provider''s own home and contact pages for its public phone and email (direct reads, no Firecrawl). Fills only empty values.', 5, true),
 ('cricos-peo', 'Course pages', 16, 'Read CRICOS contact (internal)', 'Reads the Principal Executive Officer from the CRICOS website (Firecrawl). Held for internal use; never published.', 5, true)
on conflict (jobname) do nothing;

do $post$
declare v_expected jsonb := jsonb_build_object('public.admin_provider_edit_read(uuid)', '3306e12173001cad55424308c605ee2c');
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 v2.15.234 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
