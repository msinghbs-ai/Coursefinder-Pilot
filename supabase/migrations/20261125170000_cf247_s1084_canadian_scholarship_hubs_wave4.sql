-- CF-247 s1084 (S2-Scholarship-Readers, Canadian Wave 4; Platform Admin 24 Nov 2026 21:48, SCH-FU-03): fifteen genuine scholarship listing pages at 14 Canadian providers were stored as candidates and
-- rejected as "listing_page", but never registered as hubs, so the awards listed on them were never expanded into candidates. Each is on the provider's own site, is a central entrance, international or
-- general awards list, and is not marked domestic-only. Pages marked domestic_only, faculty and department pages and award-recipient lists are not registered. None of the 14 providers is held (cap or budget).
-- Replaces: nothing
-- Retires: nothing
-- G2: no operational value here (page addresses and a read-now flag). G3: 75/48, the manual locks and the active cron count are checked before and after; no job, table, function or setting is added or changed.
set local lock_timeout = '5s';  -- fixed: lock wait for the listing rows

create temp table s1084_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1084_cron on commit drop as select count(*) n from cron.job where active;
do $g$ declare v jsonb := security.consumer_api_check_v1();
begin if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API surface is %/% (expected 75/48)', v->>'functions', v->>'relations'; end if; end $g$;

do $l$
declare
  r record; v_n int := 0; v_held int := 0;
begin
  for r in
    select * from (values
      ('687ae5b6-756a-4a2f-b4f0-bf85b68b339c'::uuid, 'https://www.douglascollege.ca/fees-and-finances/awards-bursaries-and-scholarships/scholarships-and-awards-international-students'),
      ('fe106405-7f73-4ff4-978f-3c0162b1739b'::uuid, 'https://www2.acadiau.ca/student-services/scholarships-financial-aid.html'),
      ('a787be65-254e-4fed-91d5-8aec5908d226'::uuid, 'https://algomau.ca/students/tuition-scholarships-financial-aid/awards-scholarships/entrance-scholarships/'),
      ('3e436a48-1f61-4690-9fbd-4c749f3acfef'::uuid, 'https://www.kpu.ca/scholarships-and-awards-0'),
      ('c9d6e8c8-a988-4f90-94c4-944a5bf2aec0'::uuid, 'https://www.mun.ca/scholarships/application-based-scholarships-and-awards/'),
      ('c9d6e8c8-a988-4f90-94c4-944a5bf2aec0'::uuid, 'https://www.mun.ca/scholarships/entrance-scholarships/other-entrance-scholarships/'),
      ('23d19ef5-f4b0-4a99-bb9a-16bdaf7eb6be'::uuid, 'https://www.msvu.ca/future-students/money-matters/scholarships-awards/undergraduate-scholarships/entrance-scholarships'),
      ('e7caf3bf-0dba-49e1-a654-09427531cd26'::uuid, 'https://www.niagaracollege.ca/enrolmentservices/financialaid/scholarships/entering-students/'),
      ('21818449-895c-45eb-82a6-b91bee0cece0'::uuid, 'https://www.nwpolytech.ca/financial-aid/awards-listing'),
      ('a29ecd44-67c5-4839-820e-3a5778dbc1df'::uuid, 'https://www.oldscollege.ca/admissions/scholarships-and-awards/index.html'),
      ('40abe289-b458-47dd-a035-96d339bd1248'::uuid, 'https://www.queensu.ca/registrar/financial-aid/application-required/future-students/other-awards'),
      ('7586774d-d712-42b4-9049-495b0cc9676e'::uuid, 'https://www.redeemer.ca/tuition-financial-aid/financial-aid/student-awards/'),
      ('bd1dd317-f9d8-484b-9639-c632e92c2503'::uuid, 'https://www.trentu.ca/studentfinances/scholarships-awards-bursaries/entrance-scholarships'),
      ('0d47cf4f-7389-4d92-b7a7-8a2eba6ea1e6'::uuid, 'https://www.unbc.ca/programs-and-admissions/undergraduate/scholarships-bursaries-and-awards'),
      ('681f7e51-e130-4e53-aa09-81e4b717d69d'::uuid, 'https://www.upei.ca/scholarships-and-awards/displayscholarships')
    ) t(pid, url)
  loop
    if not exists (select 1 from catalogue.providers p join ref.countries c on c.id = p.country_id where p.id = r.pid and c.iso_alpha2 = 'CA') then raise exception 'guard: provider % is not a Canadian provider', r.pid; end if;
    if not security.url_on_provider_sites(r.url, r.pid) then raise exception 'guard: % is not on the provider''s own website', r.url; end if;
    insert into pipeline.scholarship_listing_pages(provider_id, url, url_norm, source, active, status, next_read_at, added_by)
    values (r.pid, r.url, security.scholarship_url_norm(r.url), 'manual', true, 'waiting', null, security.system_actor_id())
    on conflict (provider_id, url_norm) do update set active = true, next_read_at = null,
       source = case when pipeline.scholarship_listing_pages.source = 'suggested' then 'manual' else pipeline.scholarship_listing_pages.source end,
       status = case when pipeline.scholarship_listing_pages.status = 'suggested' then 'waiting' else pipeline.scholarship_listing_pages.status end;
    v_n := v_n + 1;
    if security.fc_sch_held_v1(r.pid, true) then v_held := v_held + 1; end if;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('scholarship_coverage', 'add_listing', r.pid::text, jsonb_build_object('url', r.url, 'reason', 'Platform Admin 24 Nov 2026 21:48: Canadian Wave 4 scholarship hubs from rejected listing pages (s1084)', 'migration', '20261125170000'), security.system_actor_id());
  end loop;
  if v_n <> 15 then raise exception 'guard: % hubs registered, expected 15', v_n; end if;
  raise notice 's1084: % hubs registered and queued; % held (cap or budget)', v_n, v_held;
end $l$;

do $c$ declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'post-check: consumer API surface changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1084_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1084_cron) then raise exception 'post-check: active cron count changed'; end if;
end $c$;
