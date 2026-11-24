-- CF-247 s1046 (S2-Scholarship-Readers, Canadian Wave 2; Platform Admin 24 Nov 2026 15:13): eleven more Canadian providers get their official scholarship hub registered and read now:
-- six universities that held only department-level pages (UBC, Alberta, Simon Fraser, Lethbridge, Calgary, Manitoba) and five colleges and universities with no page (Athabasca, Cambrian, Canadore, La Cite, Loyalist).
-- Not registered, with reasons: University of Victoria (only a test host and single-award pages were found) and College of the North Atlantic (its own page says no international entrance awards).
-- Holds, measured live (rolled back, 24 Nov 2026): the listing picker (svc_scholarship_listing_next) skips a provider that security.fc_sch_held_v1(provider, true) holds. 10 of the 18 Canadian providers are held only
-- because security.fc_sch_eligible_v1 is false for them (Conestoga, Durham, Sheridan, Camosun, Algonquin, George Brown, Cambrian, Canadore, La Cite, Loyalist), so a registered hub would never be read. Lethbridge is held by the
-- per-university cap (150 of 150 units), which is spend protection and is left as it is. The eligibility branch is skipped for Canadian providers while the setting scholarship.listing_open_ca is 1; the cap and the budget switch are unchanged.
-- Replaces: security.fc_sch_held_v1(uuid,boolean) (same name and arguments; guarded edit)
-- Retires: nothing
-- G2: the switch is a setting (scholarship.listing_open_ca); the country code in the rule is the scope itself (fixed: the Platform Admin's Canadian territory).  no operational value here (a page address and a read-now flag). G3 75/48, the manual locks and the active cron count are checked before and after; no job, table or setting is added.
set local lock_timeout = '5s';  -- fixed: lock wait for the listing rows

create temp table s1046_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1046_cron on commit drop as select count(*) n from cron.job where active;
do $g$ declare v jsonb := security.consumer_api_check_v1();
begin if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API surface is %/% (expected 75/48)', v->>'functions', v->>'relations'; end if; end $g$;

-- 0. the switch (settings row, shown on Settings > Pipeline settings)
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'scholarship.listing_open_ca', 'Scholarship listing reads: Canadian providers skip the eligibility hold',
        'On (1): the scholarship listing picker and the other scholarship lanes treat a Canadian provider as eligible, so its registered hubs are read. The per-university cap and the Firecrawl budget switch still hold. Off (0): the eligibility rule applies to Canada as before.',
        'number', to_jsonb(1), 0, 1, 'on/off', 346, 'Scholarships', 'security.fc_sch_held_v1 (listing, read, discover and candidate lanes)', 'CF-247 s1046: Platform Admin 24 Nov 2026 15:13 (clear Canadian provider holds so pages lease immediately)')
on conflict do nothing;

-- 1. what the hold says today for every non-Canadian provider with a listing page (must be unchanged after the edit)
create temp table s1046_held_before on commit drop as
  select distinct l.provider_id, security.fc_sch_held_v1(l.provider_id, true) h
    from pipeline.scholarship_listing_pages l join catalogue.providers p on p.id = l.provider_id join ref.countries c on c.id = p.country_id
   where l.active and c.iso_alpha2 <> 'CA';

do $e$
declare
  v_def text := pg_get_functiondef('security.fc_sch_held_v1(uuid,boolean)'::regprocedure);
  v_old constant text := '  return p_discovery and not security.fc_sch_eligible_v1(p_provider_id);';
  v_new constant text := E'  -- s1046 (24 Nov 2026): Canadian providers skip the eligibility rule while scholarship.listing_open_ca is 1 (the cap and the budget switch above still hold)\n'
    || E'  return p_discovery and not security.fc_sch_eligible_v1(p_provider_id)\n'
    || E'    and not (coalesce((select (s.value #>> ''{}'')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = ''pipeline'' and s.key = ''scholarship.listing_open_ca''), 0) > 0\n'
    || E'             and exists (select 1 from catalogue.providers p join ref.countries c on c.id = p.country_id where p.id = p_provider_id and c.iso_alpha2 = ''CA''));';
begin
  if position('s1046 (24 Nov 2026)' in v_def) > 0 then return; end if;
  if position('s981 (23 Nov 2026, IQ-00555)' in v_def) = 0 then raise exception 'guard: security.fc_sch_held_v1 is not the s981 definition this change edits'; end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'guard: the eligibility line must appear exactly once'; end if;
  execute replace(v_def, v_old, v_new);
end $e$;

do $p$
begin
  if exists (select 1 from s1046_held_before b where security.fc_sch_held_v1(b.provider_id, true) is distinct from b.h) then
    raise exception 'post-check: the hold changed for a non-Canadian provider';
  end if;
end $p$;

do $l$
declare
  r record; v_n int := 0; v_held int := 0;
begin
  for r in
    select * from (values
      ('175462f3-59ea-4370-9c80-e7a06b100137'::uuid, 'https://students.ubc.ca/finances/awards-scholarships-bursaries/awards-international/'),
      ('db436563-4650-4820-bd76-0695afcc953d'::uuid, 'https://www.ualberta.ca/en/admissions/tuition-and-scholarships/international-entrance-scholarships/index.html'),
      ('d47b6006-396a-4785-b2ae-15186c3e7709'::uuid, 'https://www.sfu.ca/students/financialaid/international/international/'),
      ('b509ab5c-87b2-4040-8385-d1ce610c7263'::uuid, 'https://www.ulethbridge.ca/international/facilities-and-services'),
      ('ad7bb2f7-ed12-4181-b5c4-d071db14bfda'::uuid, 'https://www.ucalgary.ca/registrar/finances/awards/prestige'),
      ('cffa9cab-0a3b-458b-8383-483ce622c9c3'::uuid, 'https://umanitoba.ca/financial-aid-and-awards/international'),
      ('e450a320-27d7-4ca2-8ad6-cafa266df869'::uuid, 'https://www.athabascau.ca/support-services/financial-aid-and-awards/index.html'),
      ('e924fe06-feb7-472b-9035-4ccebdf9fe67'::uuid, 'https://cambriancollege.ca/1500-entrance-scholarship'),
      ('425b1fad-a4ef-4a21-8590-c7fa9b671107'::uuid, 'https://www.canadorecollege.ca/canadore-international/international-students/financial-assistance'),
      ('5675f806-596a-4982-bd4a-f068e013f974'::uuid, 'https://www.collegelacite.ca/bourses'),
      ('6907453a-faa4-4c60-bc64-e2f2ea476a15'::uuid, 'https://loyalistcollege.com/admissions/paying-for-college/donor-supported-bursaries-and-scholarships/')
    ) t(pid, url)
  loop
    if not exists (select 1 from catalogue.providers p where p.id = r.pid) then raise exception 'guard: provider % not found', r.pid; end if;
    if not security.url_on_provider_sites(r.url, r.pid) then raise exception 'guard: % is not on the provider''s own website', r.url; end if;
    insert into pipeline.scholarship_listing_pages(provider_id, url, url_norm, source, active, status, next_read_at, added_by)
    values (r.pid, r.url, security.scholarship_url_norm(r.url), 'manual', true, 'waiting', null, security.system_actor_id())
    on conflict (provider_id, url_norm) do update set active = true, next_read_at = null,
       source = case when pipeline.scholarship_listing_pages.source = 'suggested' then 'manual' else pipeline.scholarship_listing_pages.source end,
       status = case when pipeline.scholarship_listing_pages.status = 'suggested' then 'waiting' else pipeline.scholarship_listing_pages.status end;
    v_n := v_n + 1;
    if security.fc_sch_held_v1(r.pid, true) then v_held := v_held + 1; end if;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('scholarship_coverage', 'add_listing', r.pid::text, jsonb_build_object('url', r.url, 'reason', 'Platform Admin 24 Nov 2026 15:13: Canadian Wave 2 scholarship hubs (s1046)', 'migration', '20261124200000'), security.system_actor_id());
  end loop;
  if v_n <> 11 then raise exception 'guard: % hubs registered, expected 11', v_n; end if;
  raise notice 's1046: % hubs registered and queued; % still held after the exemption (cap or budget)', v_n, v_held;
end $l$;

do $c$ declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'post-check: consumer API surface changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1046_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1046_cron) then raise exception 'post-check: active cron jobs changed'; end if;
end $c$;
