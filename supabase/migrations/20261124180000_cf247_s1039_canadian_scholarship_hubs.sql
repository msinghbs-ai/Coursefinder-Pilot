-- CF-247 s1039 (S2-Scholarship-Readers, Canadian territory; Platform Admin 24 Nov 2026 14:58 and 15:00): seven Canadian providers with no scholarship listing page get their
-- official international scholarship hub registered and read now. The s1035 and s1037 splitters read them; the existing scope functions link university-wide merit awards to courses.
-- Replaces: nothing
-- Retires: nothing
-- G2: no value here is operational (a page address and a read-now flag). G3 75/48, the manual locks and the active cron count are checked before and after; no job, table or setting is added.
set local lock_timeout = '5s';  -- fixed: lock wait for the listing rows

create temp table s1039_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1039_cron on commit drop as select count(*) n from cron.job where active;
do $g$ declare v jsonb := security.consumer_api_check_v1();
begin if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API surface is %/% (expected 75/48)', v->>'functions', v->>'relations'; end if; end $g$;

do $l$
declare
  r record; v_n int := 0; v_held int := 0;
begin
  for r in
    select * from (values
      ('7b35d38d-08da-4aec-9110-c60e29dc0b45'::uuid, 'https://www.conestogac.on.ca/international/apply-to-conestoga/awards-and-scholarships'),
      ('c79c40ee-0939-4e2e-b9b3-b4e2d772e667'::uuid, 'https://durhamcollege.ca/info-for/international/study-dc/scholarships'),
      ('cc24d184-d9e1-4d8a-b6e5-812b3578d7ac'::uuid, 'https://www.sheridancollege.ca/admissions/financial-aid-and-awards/awards-and-scholarships/international-entrance-scholarship'),
      ('30f2a374-62e8-4be5-81fd-b94f033ea937'::uuid, 'https://camosun.ca/international/international-tuition-fees/scholarships-international-students'),
      ('4682bc05-a9de-44bb-ae66-ad02c9717a2d'::uuid, 'https://www.algonquincollege.com/financial-aid/awards-bursaries-scholarships/'),
      ('dc671c35-5660-48ff-bb3b-31be971c0d9f'::uuid, 'https://www.georgebrown.ca/apply/financial-aid/awards-and-scholarships/types-of-awards/international'),
      ('50efbfe2-b917-4cf7-be50-4a53c9a718d7'::uuid, 'https://www.macewan.ca/apply-enrol/fees-finances/scholarships-awards-bursaries/entrance-scholarships/')
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
    values ('scholarship_coverage', 'add_listing', r.pid::text, jsonb_build_object('url', r.url, 'reason', 'Platform Admin 24 Nov 2026 15:00: Canadian international scholarship hubs (s1039)', 'migration', '20261124180000'), security.system_actor_id());
  end loop;
  if v_n <> 7 then raise exception 'guard: % hubs registered, expected 7', v_n; end if;
  raise notice 's1039: % hubs registered and queued; % of them under a provider-level hold (reported, not changed)', v_n, v_held;
end $l$;

do $c$ declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'post-check: consumer API surface changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1039_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1039_cron) then raise exception 'post-check: active cron jobs changed'; end if;
end $c$;
