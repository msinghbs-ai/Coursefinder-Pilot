-- CF-247 s1097 (S2-Scholarship-Readers, Canadian Wave 6; Platform Admin 24 Nov 2026 23:52, Admin #1030): two official scholarship pages are registered as hubs for Canadian providers that have active courses and no hub with items:
-- Okanagan College (the central awards, scholarships and bursaries page, 80 active courses; its one existing hub is the Indigenous awards page) and Coast Mountain College (the entrance awards page, which lists the International Student Entrance Awards).
-- Not registered, with reason: La Cite collegiale (no official international award page found), Humber College (official pages are on humber.ca but the provider record's website is humberetc.ca, so the own-site check refuses them),
-- College of the North Atlantic (its own page lists no international entrance awards) and North Island College (foundation host only).
-- Replaces: nothing
-- Retires: nothing
-- G2: no operational value here (page addresses and a read-now flag). G3: 75/48, the manual locks and the active cron count are checked before and after; no job, table, function or setting is added or changed.
set local lock_timeout = '5s';  -- fixed: lock wait for the listing rows

create temp table s1097_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1097_cron on commit drop as select count(*) n from cron.job where active;
do $g$ declare v jsonb := security.consumer_api_check_v1();
begin if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API surface is %/% (expected 75/48)', v->>'functions', v->>'relations'; end if; end $g$;

do $l$
declare
  r record; v_n int := 0; v_held int := 0;
begin
  for r in
    select * from (values
      ('5b6ad653-99f7-4347-a56e-f0d2928bd34d'::uuid, 'https://www.okanagancollege.ca/financial-aid-and-awards/awards-scholarships-and-bursaries'),
      ('3a48beb7-d61f-468c-b93c-6fa61ab96921'::uuid, 'https://coastmountaincollege.ca/student-services/financial-aid/entrance-awards')
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
    values ('scholarship_coverage', 'add_listing', r.pid::text, jsonb_build_object('url', r.url, 'reason', 'Platform Admin 24 Nov 2026 23:52: Canadian Wave 6 scholarship hubs (s1097)', 'migration', '20261126030000'), security.system_actor_id());
  end loop;
  if v_n <> 2 then raise exception 'guard: % hubs registered, expected 2', v_n; end if;
  raise notice 's1097: % hubs registered and queued; % held (cap or budget)', v_n, v_held;
end $l$;

do $c$ declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'post-check: consumer API surface changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1097_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1097_cron) then raise exception 'post-check: active cron count changed'; end if;
end $c$;
