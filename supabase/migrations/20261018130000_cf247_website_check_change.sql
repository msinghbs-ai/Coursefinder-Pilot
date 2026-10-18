-- CF-247 bug 18/10-01 (18 Oct 2026, v2.15.288). Platform Admin 20:35 (screenshot: Layer 2 › Adapter builder, step 1.1 Website, Sydney
-- Film School): "add to bug/fix: Website - should have to feature to validate or change the website in the adapter builder."
-- New here:
-- 1 pipeline.provider_website_checks: one row per Check or Change asked for in step 1.1. The worker (coverage-sweep v0.31.0, mode
--   site_check) reads the address's home page now (directly; through the scraper, about 1 credit, only when the site refuses a direct
--   read) and records what it found: does it answer, is it a third-party site, is the provider's CRICOS code on it, is it the site the
--   register lists, is the provider's name on the home page, does the address fit the name.
-- 2 Verdict (security.provider_website_verdict_v1): Verified (CRICOS code, register-listed site or DLI number), Likely (name on the home
--   page or the address fits the name), Failed (does not answer, third-party, or none of these).
-- 3 public.admin_provider_website_check(action, args): list (latest checks), check (Curator and above), change (Platform Admin, with a
--   reason; saved only when the check is Verified or Likely). A change is saved through public.admin_provider_website_set (locked,
--   logged) as the person who asked; the generic course-page recipe moves to the new address; course-page searches that found nothing
--   are queued again; a stopped or held search is resumed (as "Search again" does); contacts and central pages are looked for again.
--   A second site of the same provider can be given: its pages are accepted as course pages too (an extra pattern in the recipe).
--   Course pages already found on the old address are counted and left for the relink step.
-- 4 Job provider-website-check (every 5 minutes) starts the worker only when a check is waiting; the RPC also starts it at once.
-- Nothing the website or Zoho reads changes shape (Decision 266): catalogue.providers.website keeps its column and type.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"public.admin_provider_website_set(uuid,text)": "7de75fd98eb315284f59ed306b9e3822", "public.admin_firecrawl_search_resume(uuid,text)": "a557f380714b8763065a749fd11ab04b", "pipeline.svc_pilot_submit_nonce(text,jsonb)": "5ea5b5f8c20b934645dca7f0211db658"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(pg_get_functiondef(v_sig::regprocedure)) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change relies on', v_sig;
    end if;
  end loop;
end $guard$;

-- settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'batch.website_check', 'Website checks per worker run (Adapter builder 1.1)', 'Each worker run reads this many waiting Check website or Change website requests.', 'number', '5', 1, 10, 'checks', 316, 'CF-247 bug 18/10-01, 18 Oct 2026', 'Enrichment', 'job provider-website-check, public.admin_provider_website_check')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.provider_website_checks (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  url text not null check (url ~* '^https?://[^\s/]+\.[^\s]+$'),
  action text not null check (action in ('check', 'change')),
  extra_site text check (extra_site is null or extra_site ~* '^https?://[^\s/]+\.[^\s]+$'),
  reason text,
  requested_by uuid not null,
  requested_at timestamptz not null default now(),
  state text not null default 'queued' check (state in ('queued', 'leased', 'done')),
  leased_until timestamptz,
  attempts int not null default 0,
  result jsonb,
  verdict text check (verdict in ('verified', 'likely', 'failed')),
  why text,
  checked_at timestamptz,
  applied boolean not null default false,
  applied_at timestamptz,
  apply_note jsonb
);
comment on table pipeline.provider_website_checks is 'Adapter builder 1.1 (bug 18/10-01): Check website and Change website requests, what the worker found on the home page, the verdict, and for a change what was saved and restarted.';
create index if not exists provider_website_checks_provider_idx on pipeline.provider_website_checks (provider_id, requested_at desc);
create index if not exists provider_website_checks_waiting_idx on pipeline.provider_website_checks (requested_at) where state <> 'done';
alter table pipeline.provider_website_checks enable row level security;

-- the provider's addresses as a list (a few records hold two sites in one field: "https://a.edu.au, www.b.edu.au")
CREATE OR REPLACE FUNCTION security.provider_website_list_v1(p_website text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select coalesce(array_agg(case when x ~* '^https?://' then x else 'https://' || x end order by n), '{}')
    from (select btrim(x) x, n from regexp_split_to_table(coalesce(p_website, ''), '\s*(,|;|\s+and\s+|\s)\s*') with ordinality t(x, n)) s
   where s.x ~* '^(https?://)?[a-z0-9-]+(\.[a-z0-9-]+)+(/\S*)?$'
$function$;

CREATE OR REPLACE FUNCTION security.provider_website_verdict_v1(p_result jsonb, OUT verdict text, OUT why text)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case when not coalesce((p_result->>'answers')::boolean, false) then 'failed'
              when coalesce((p_result->>'third_party')::boolean, false) then 'failed'
              when coalesce((p_result->>'cricos_on_site')::boolean, false) or coalesce((p_result->>'register_match')::boolean, false)
                   or p_result->>'name_basis' = 'dli_number' then 'verified'
              when nullif(p_result->>'name_basis', '') is not null or coalesce((p_result->>'domain_fits')::boolean, false) then 'likely'
              else 'failed' end,
         case when not coalesce((p_result->>'answers')::boolean, false) then 'the home page did not answer' || coalesce(' (' || nullif(p_result->>'http', '') || ')', '')
              when coalesce((p_result->>'third_party')::boolean, false) then 'a third-party site (a course directory or similar), not the provider''s own'
              when coalesce((p_result->>'cricos_on_site')::boolean, false) then 'the provider''s CRICOS code ' || coalesce(p_result->>'cricos_code', '') || ' is on the home page'
              when coalesce((p_result->>'register_match')::boolean, false) then 'it is the site the register lists'
              when p_result->>'name_basis' = 'dli_number' then 'the provider''s DLI number is on the home page'
              when nullif(p_result->>'name_basis', '') is not null then 'the provider''s name is on the home page' || case when nullif(p_result->>'cricos_code', '') is not null then ', but not its CRICOS code' else '' end
              when coalesce((p_result->>'domain_fits')::boolean, false) then 'the address fits the provider''s name' || case when nullif(p_result->>'cricos_code', '') is not null then ', but its CRICOS code is not on the home page' else '' end
              else 'neither the provider''s name nor its CRICOS code is on the home page' end
$function$;

-- starts the worker when a check is waiting (no edge call otherwise)
CREATE OR REPLACE FUNCTION security.provider_website_check_kick_v1()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not exists (select 1 from pipeline.provider_website_checks c where c.state = 'queued' or (c.state = 'leased' and c.leased_until < now())) then return false; end if;
  perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'site_check', 'limit', security.pipeline_num_v1('batch.website_check', 5)::int));
  return true;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_provider_website_check_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select c.id from pipeline.provider_website_checks c
     where (c.state = 'queued' or (c.state = 'leased' and c.leased_until < now()))
       and c.attempts < 3  -- fixed: retry guard for a check the worker could not finish
     order by c.requested_at
     limit greatest(1, least(coalesce(p_limit, 5), 10)) for update skip locked),
  upd as (update pipeline.provider_website_checks c set state = 'leased', attempts = c.attempts + 1,
                 leased_until = now() + interval '10 minutes'  -- fixed: worker lease
            from pick where c.id = pick.id returning c.id, c.provider_id, c.url)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'provider_id', u.provider_id, 'url', u.url,
           'name', coalesce(p.display_name, p.canonical_name), 'trading', p.short_name, 'country', security.coverage_country(u.provider_id),
           'cricos', (select min(upper(pr.registration_code)) from catalogue.provider_registrations pr where pr.provider_id = u.provider_id and lower(pr.registration_scheme) = 'cricos'),
           'dli', (select min(upper(pr.registration_code)) from catalogue.provider_registrations pr where pr.provider_id = u.provider_id and lower(pr.registration_scheme) = 'ircc_dli'),
           'register_site', (select d.website from pipeline.coverage_provider_discovery d where d.provider_id = u.provider_id and d.site_source like 'search_verified_register%'))), '[]'::jsonb)
    into v from upd u join catalogue.providers p on p.id = u.provider_id;
  return v;
end $function$;

-- saves a checked change as the person who asked, then restarts what depends on the website
CREATE OR REPLACE FUNCTION security.provider_website_change_apply_v1(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_c pipeline.provider_website_checks%rowtype; v_url text; v_old text; v_dom text; v_old_dom text; v_extra text; v_rec pipeline.course_link_recipes%rowtype;
        v_requeued int := 0; v_old_pages int := 0; v_recipe text; v_note jsonb;
begin
  select * into v_c from pipeline.provider_website_checks c where c.id = p_id for update;
  if v_c.action <> 'change' or v_c.applied or v_c.verdict not in ('verified', 'likely') then return null; end if;
  v_url := coalesce(nullif(v_c.result->>'final_url', ''), regexp_replace(v_c.url, '^(https?://[^/?#]+).*$', '\1'));
  select nullif(btrim(p.website), '') into v_old from catalogue.providers p where p.id = v_c.provider_id;
  v_dom := security.site_host_v1(v_url);
  v_old_dom := security.site_host_v1((security.provider_website_list_v1(v_old))[1]);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_c.requested_by::text, 'role', 'authenticated')::text, true);
  perform public.admin_provider_website_set(v_c.provider_id, v_url);
  perform set_config('request.jwt.claims', '', true);
  -- the generic recipe follows the new address; a recipe built for this provider's site by hand or by an adapter is kept
  select * into v_rec from pipeline.course_link_recipes r where r.provider_id = v_c.provider_id;
  if v_rec.provider_id is not null and v_dom is not null and v_rec.search_domain <> v_dom then
    if coalesce(v_rec.notes, '') like 'Generic recipe%' then
      update pipeline.course_link_recipes set search_domain = v_dom, active = true, updated_at = now(), updated_by = v_c.requested_by,
             patterns = jsonb_build_array(jsonb_build_object(
               're', '(?i)^https?://([a-z0-9-]+\.)*' || regexp_replace(v_dom, '\.', '\\.', 'g')
                     || '/(?!.*\.(pdf|docx?|xlsx?|pptx?|jpe?g|png|gif|svg|zip)$)(?!(.*/)?(news|events?|blog|staff|people|media|search|tags?|category)(/|$)).+$',
               'rep', '\&')),
             notes = 'Generic recipe: any page on the provider''s own site, from a website changed and checked in the Adapter builder (bug 18/10-01, 18 Oct 2026)'
       where provider_id = v_c.provider_id;
      v_recipe := 'moved to ' || v_dom;
    else
      v_recipe := 'kept: a recipe built for ' || v_rec.search_domain || ' (review it in step 3)';
    end if;
  else
    v_recipe := case when v_rec.provider_id is null then 'none' else 'unchanged' end;
  end if;
  -- a second site of the same provider: its pages are accepted as course pages too
  v_extra := security.site_host_v1(v_c.extra_site);
  if v_extra is not null and v_extra <> coalesce(v_dom, '') then
    update pipeline.course_link_recipes set updated_at = now(), updated_by = v_c.requested_by,
           patterns = patterns || jsonb_build_array(jsonb_build_object(
             're', '(?i)^https?://([a-z0-9-]+\.)*' || regexp_replace(v_extra, '\.', '\\.', 'g')
                   || '/(?!.*\.(pdf|docx?|xlsx?|pptx?|jpe?g|png|gif|svg|zip)$)(?!(.*/)?(news|events?|blog|staff|people|media|search|tags?|category)(/|$)).+$',
             'rep', '\&', 'extra_site', v_extra))
     where provider_id = v_c.provider_id and not (patterns::text like '%"extra_site": "' || v_extra || '"%');
  end if;
  -- searches that found nothing on the old address are tried again on the new one
  update pipeline.course_link_search s set state = 'queued', attempts = 0, query = null, results = null, candidates = null, cand_idx = null, req_id = null,
         bound_url = null, sent_at = null, done_at = null, queued_at = now(), requested_at = now()
   where s.provider_id = v_c.provider_id and s.state = 'none'
     and exists (select 1 from catalogue.courses c where c.id = s.course_id and c.lifecycle_status = 'active')
     and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = s.course_id);
  get diagnostics v_requeued = row_count;
  -- a stopped or held course-page search is resumed, as Search again does
  insert into pipeline.firecrawl_search_resumes(provider_id, reason, set_by)
  values (v_c.provider_id, left('Website changed in the Adapter builder: ' || coalesce(v_c.reason, ''), 400), v_c.requested_by);
  -- Fill in from website: contacts and central pages are looked for again
  insert into pipeline.provider_central_search(provider_id, state, requested_at) values (v_c.provider_id, 'queued', now())
  on conflict (provider_id) do update set state = 'queued', requested_at = now(), leased_until = null, attempts = 0, updated_at = now();
  update pipeline.provider_contact_checks set checked_at = now() - interval '91 days', outcome = 'requested'  -- fixed: one day past the contacts re-check window, as Fill in from website does
   where provider_id = v_c.provider_id and kind = 'public_general';
  -- course pages already found on the old address are left for the relink step
  if v_old_dom is not null and v_old_dom <> coalesce(v_dom, '') then
    select count(*) into v_old_pages from pipeline.coverage_course_pages g join catalogue.courses c on c.id = g.course_id
     where c.provider_id = v_c.provider_id and security.site_host_v1(g.url) like '%' || v_old_dom;
  end if;
  v_note := jsonb_build_object('saved', v_url, 'before', v_old, 'recipe', v_recipe, 'extra_site', v_extra, 'searches_queued', v_requeued,
                               'search_resumed', true, 'contacts_and_central_pages', 'queued', 'pages_on_old_address', v_old_pages);
  update pipeline.provider_website_checks set applied = true, applied_at = now(), apply_note = v_note where id = p_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('provider', 'website_change', v_c.provider_id::text, v_note || jsonb_build_object('reason', v_c.reason, 'verdict', v_c.verdict, 'why', v_c.why, 'check_id', p_id, 'change', 'CF-247 bug 18/10-01'), v_c.requested_by);
  return v_note;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_provider_website_check_record(p_id uuid, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_v record; v_note jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_v from security.provider_website_verdict_v1(coalesce(p_result, '{}'::jsonb));
  update pipeline.provider_website_checks set state = 'done', leased_until = null, result = p_result, verdict = v_v.verdict, why = v_v.why, checked_at = now()
   where id = p_id and state <> 'done';
  if not found then return null; end if;
  begin
    v_note := security.provider_website_change_apply_v1(p_id);
  exception when others then
    perform set_config('request.jwt.claims', '', true);
    update pipeline.provider_website_checks set apply_note = jsonb_build_object('error', left(sqlerrm, 300)) where id = p_id;
  end;
  return jsonb_build_object('verdict', v_v.verdict, 'why', v_v.why, 'applied', v_note);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_provider_website_check(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := coalesce(security.current_role_rank(), 0); v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_url text := btrim(coalesce(p_args->>'url', ''));
        v_extra text := nullif(btrim(coalesce(p_args->>'extra_site', '')), ''); v_reason text := nullif(btrim(coalesce(p_args->>'reason', '')), ''); v_site text; v_id uuid;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select nullif(btrim(p.website), '') into v_site from catalogue.providers p where p.id = v_pid;
  if not found then raise exception 'choose a provider'; end if;
  if p_action = 'list' then
    return jsonb_build_object('website', v_site, 'sites', to_jsonb(security.provider_website_list_v1(v_site)),
      'can_check', true, 'can_change', v_rank >= 6,
      'checks', coalesce((select jsonb_agg(to_jsonb(x) order by x.requested_at desc) from (
         select c.id, c.url, c.action, c.extra_site, c.reason, c.requested_at, c.state, c.verdict, c.why, c.checked_at, c.applied, c.apply_note,
                c.result - 'worker' as result
           from pipeline.provider_website_checks c where c.provider_id = v_pid order by c.requested_at desc
          limit 5) x), '[]'::jsonb));  -- fixed: the five latest checks are shown
  end if;
  if p_action not in ('check', 'change') then raise exception 'unknown action %', p_action; end if;
  if p_action = 'change' and v_rank < 6 then raise exception 'Platform Admin required to change a website' using errcode = '42501'; end if;
  if v_url = '' and p_action = 'check' then v_url := (security.provider_website_list_v1(v_site))[1]; end if;
  if v_url !~* '^https?://' and v_url ~* '^[a-z0-9-]+(\.[a-z0-9-]+)+' then v_url := 'https://' || v_url; end if;
  if coalesce(v_url, '') !~* '^https?://[^\s/,;]+\.[^\s,;]+$' then raise exception 'enter one full web address starting with https://'; end if;
  if v_extra is not null and v_extra !~* '^https?://' then v_extra := 'https://' || v_extra; end if;
  if v_extra is not null and v_extra !~* '^https?://[^\s/,;]+\.[^\s,;]+$' then raise exception 'the other site must be one web address'; end if;
  if p_action = 'change' and length(coalesce(v_reason, '')) < 4 then raise exception 'a reason is required'; end if;
  if security.third_party_host_v1(v_url) then raise exception 'that is a third-party site (a course directory or similar), not the provider''s own website'; end if;
  if exists (select 1 from pipeline.provider_website_checks c where c.provider_id = v_pid and c.state <> 'done') then raise exception 'a check for this provider is already running; wait for its result'; end if;
  insert into pipeline.provider_website_checks(provider_id, url, action, extra_site, reason, requested_by)
  values (v_pid, v_url, p_action, case when p_action = 'change' then v_extra end, v_reason, auth.uid()) returning id into v_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('provider', 'website_' || p_action || '_asked', v_pid::text, jsonb_build_object('url', v_url, 'extra_site', v_extra, 'reason', v_reason, 'check_id', v_id, 'change', 'CF-247 bug 18/10-01'), auth.uid());
  perform security.provider_website_check_kick_v1();
  return jsonb_build_object('id', v_id, 'url', v_url, 'action', p_action, 'state', 'queued');
end $function$;

revoke execute on function security.provider_website_list_v1(text), security.provider_website_verdict_v1(jsonb), security.provider_website_check_kick_v1(),
  security.provider_website_change_apply_v1(uuid) from public, anon, authenticated;
revoke execute on function public.svc_provider_website_check_next(integer), public.svc_provider_website_check_record(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.svc_provider_website_check_next(integer), public.svc_provider_website_check_record(uuid, jsonb) to service_role;
revoke execute on function public.admin_provider_website_check(text, jsonb) from public, anon;
grant execute on function public.admin_provider_website_check(text, jsonb) to authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('provider-website-check', 'Course pages', 47, 'Website checks (Adapter builder 1.1)', 'Every 5 minutes: starts the worker for Check website and Change website requests still waiting (the request itself starts it at once).', 4, true)
on conflict (jobname) do nothing;
select cron.schedule('provider-website-check', '*/5 * * * *', $$select security.provider_website_check_kick_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.provider_website_checks', 'L2 read', 'Adapter builder 1.1: website checks and changes, findings and verdicts', 'active', '20261018130000'),
 ('job', 'provider-website-check', 'L2 read', 'Starts the worker for waiting website checks', 'active', '20261018130000'),
 ('function', 'public.admin_provider_website_check', 'L2 read', 'Adapter builder 1.1: list, check, change a website', 'active', '20261018130000'),
 ('function', 'public.svc_provider_website_check_next', 'L2 read', 'Worker: claims waiting website checks', 'active', '20261018130000'),
 ('function', 'public.svc_provider_website_check_record', 'L2 read', 'Worker: records a website check and applies a checked change', 'active', '20261018130000'),
 ('function', 'security.provider_website_change_apply_v1', 'L2 read', 'Saves a checked website change and restarts searches', 'active', '20261018130000'),
 ('function', 'security.provider_website_verdict_v1', 'L2 read', 'Verified, Likely or Failed from what the worker found', 'active', '20261018130000'),
 ('function', 'security.provider_website_list_v1', 'L2 read', 'Splits a website field holding several addresses', 'active', '20261018130000'),
 ('function', 'security.provider_website_check_kick_v1', 'L2 read', 'Starts the worker only when a check waits', 'active', '20261018130000')
on conflict (kind, name) do nothing;

do $post$
begin
  if security.provider_website_list_v1('https://www.sydneyfilmschool.com.au, www.sydneyactorsschool.edu.au') <> array['https://www.sydneyfilmschool.com.au', 'https://www.sydneyactorsschool.edu.au'] then raise exception 'bug 18/10-01 post-check: list (comma)'; end if;
  if security.provider_website_list_v1('https://www.sri.edu.au and www.srienglish.edu.au') <> array['https://www.sri.edu.au', 'https://www.srienglish.edu.au'] then raise exception 'bug 18/10-01 post-check: list (and)'; end if;
  if security.provider_website_list_v1('https://www.ihbrisbane.com.au; www.alscertificates.com') <> array['https://www.ihbrisbane.com.au', 'https://www.alscertificates.com'] then raise exception 'bug 18/10-01 post-check: list (semicolon)'; end if;
  if security.provider_website_list_v1('https://www.unimelb.edu.au/') <> array['https://www.unimelb.edu.au/'] then raise exception 'bug 18/10-01 post-check: list (one)'; end if;
  if (security.provider_website_verdict_v1('{"answers": true, "cricos_on_site": true, "cricos_code": "00116K"}')).verdict <> 'verified' then raise exception 'bug 18/10-01 post-check: verified'; end if;
  if (security.provider_website_verdict_v1('{"answers": true, "name_basis": "name_on_home_page", "cricos_code": "00116K"}')).verdict <> 'likely' then raise exception 'bug 18/10-01 post-check: likely'; end if;
  if (security.provider_website_verdict_v1('{"answers": true, "third_party": true, "cricos_on_site": true}')).verdict <> 'failed' then raise exception 'bug 18/10-01 post-check: third party'; end if;
  if (security.provider_website_verdict_v1('{"answers": false, "http": 404}')).verdict <> 'failed' then raise exception 'bug 18/10-01 post-check: no answer'; end if;
  if not exists (select 1 from cron.job where jobname = 'provider-website-check') then raise exception 'bug 18/10-01 post-check: job'; end if;
  if (select count(*) from pipeline.component_register where introduced_in = '20261018130000') <> 9 then raise exception 'bug 18/10-01 post-check: register'; end if;
end $post$;
