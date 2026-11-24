-- CF-247 s1044 (S2-Scholarship-Readers, Canadian Wave 2; Platform Admin 24 Nov 2026 15:13): eleven more Canadian providers get their official scholarship hub registered and read now:
-- six universities that held only department-level pages (UBC, Alberta, Simon Fraser, Lethbridge, Calgary, Manitoba) and five colleges and universities with no page (Athabasca, Cambrian, Canadore, La Cite, Loyalist).
-- Not registered, with reasons: University of Victoria (only a test host and single-award pages were found) and College of the North Atlantic (its own page says no international entrance awards).
-- The provider-level scholarship hold (security.fc_sch_held_v1) governs paid Firecrawl use only; a direct read is not held by it, so no exemption is added (the count is reported below).
-- Replaces: nothing
-- Retires: nothing
-- G2: no operational value here (a page address and a read-now flag). G3 75/48, the manual locks and the active cron count are checked before and after; no job, table or setting is added.
set local lock_timeout = '5s';  -- fixed: lock wait for the listing rows

create temp table s1044_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1044_cron on commit drop as select count(*) n from cron.job where active;
do $g$ declare v jsonb := security.consumer_api_check_v1();
begin if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API surface is %/% (expected 75/48)', v->>'functions', v->>'relations'; end if; end $g$;

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
    values ('scholarship_coverage', 'add_listing', r.pid::text, jsonb_build_object('url', r.url, 'reason', 'Platform Admin 24 Nov 2026 15:13: Canadian Wave 2 scholarship hubs (s1044)', 'migration', '20261124200000'), security.system_actor_id());
  end loop;
  if v_n <> 11 then raise exception 'guard: % hubs registered, expected 11', v_n; end if;
  raise notice 's1044: % hubs registered and queued; % of them under a provider-level Firecrawl hold (reported, not changed)', v_n, v_held;
end $l$;

do $c$ declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'post-check: consumer API surface changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1044_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1044_cron) then raise exception 'post-check: active cron jobs changed'; end if;
end $c$;
