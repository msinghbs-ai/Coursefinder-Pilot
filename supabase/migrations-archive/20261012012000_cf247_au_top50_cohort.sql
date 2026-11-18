-- CF-247 v2.15.262 (Platform Admin, 12 Oct 2026 22:22): "Maintain the uni names and data enrichment based on it. I'm not sure of the
-- criteria you are using to pick unis; they might be small ones or without even websites and we are burning resources on them. At least
-- from CRICOS we know the number of courses. Give me the top 50 unis with maximum courses in Australia and try our mechanism over them.
-- Prepare the list based on courses and prioritise them for the run." Decisions (22:3x): "Top 50 AU providers by courses";
-- "Universities first; hold small ones".
-- Found: none of the 37 Australian universities with 100+ CRICOS courses had been through onboarding (only Notre Dame had a row); the
-- pilot's AU members were picked by stage, not size. This migration:
--   1 cohort au-top-2026-10-12: the 50 active Australian providers with the most active CRICOS courses (course code of the CRICOS
--     shape, from the CRICOS-based catalogue), each with its baseline, tracked hourly like the pilot;
--   2 each is queued ahead of everything else, largest first (priority 400000 + CRICOS courses); a provider with no onboarding row gets
--     one; a queued row is moved up; a row stopped on an error is queued again; other rows carry on as they are;
--   3 queued (not started) members of pilot-2026-10-12 with fewer than 30 active courses are held at the back of the queue
--     (priority -1). Rows already running finish.
-- Data only; nothing dropped or deleted.

create temporary table t_top as
select x.provider_id, x.courses, row_number() over (order by x.courses desc, x.provider_id) rk
  from (select c.provider_id, count(*) courses from catalogue.courses c join catalogue.providers p on p.id = c.provider_id
         where c.lifecycle_status = 'active' and c.course_code ~ '^[0-9]{6}[0-9A-Z]$' and p.lifecycle_status = 'active'
           and security.coverage_country(c.provider_id) = 'AU'
         group by 1) x
 order by x.courses desc, x.provider_id limit 50;

insert into pipeline.onboarding_pilot(cohort, provider_id, country, picked_at, baseline)
select 'au-top-2026-10-12', t.provider_id, 'AU', now(), security.provider_fill_counts_v1(t.provider_id) || jsonb_build_object('cricos_courses', t.courses, 'rank', t.rk)
  from t_top t
on conflict (cohort, provider_id) do nothing;

insert into pipeline.provider_onboarding(provider_id, status, source, requested_by, reason, priority, note)
select t.provider_id, 'queued', 'manual', '63ba56cb-48d4-4169-98c2-7c4d1f72925b',
       format('Platform Admin 12 Oct 2026 22:22: top 50 Australian providers by CRICOS courses (rank %s, %s courses)', t.rk, t.courses),
       400000 + t.courses, 'Queued first: top 50 Australian providers by CRICOS courses.'
  from t_top t
 where not exists (select 1 from pipeline.provider_onboarding o where o.provider_id = t.provider_id);

update pipeline.provider_onboarding o set priority = 400000 + t.courses, updated_at = now()
  from t_top t where o.provider_id = t.provider_id and o.status = 'queued';

update pipeline.provider_onboarding o set status = 'queued', stop_reason = null, attempts = 0, job_id = null, priority = 400000 + t.courses,
       note = 'Queued again: top 50 Australian providers by CRICOS courses.', updated_at = now()
  from t_top t where o.provider_id = t.provider_id and o.status = 'stopped' and o.stop_reason in ('error', 'capture_failed', 'proposal_failed');

update pipeline.provider_onboarding o set priority = -1, note = 'Held at the back of the queue: fewer than 30 courses (Platform Admin 12 Oct 2026 22:22, top 50 by CRICOS courses first).', updated_at = now()
 where o.status = 'queued'
   and exists (select 1 from pipeline.onboarding_pilot m where m.cohort = 'pilot-2026-10-12' and m.provider_id = o.provider_id)
   and not exists (select 1 from t_top t where t.provider_id = o.provider_id)
   and (select count(*) from catalogue.courses c where c.provider_id = o.provider_id and c.lifecycle_status = 'active') < 30;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('onboarding', 'cohort', 'au-top-2026-10-12',
        jsonb_build_object('reason', 'Platform Admin 12 Oct 2026 22:22: top 50 Australian providers by CRICOS courses, first; small pilot rows held',
                           'members', (select count(*) from pipeline.onboarding_pilot where cohort = 'au-top-2026-10-12'),
                           'held', (select count(*) from pipeline.provider_onboarding where priority = -1 and status = 'queued'), 'change', 'CF-247 v2.15.262'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

do $chk$ begin
  if (select count(*) from pipeline.onboarding_pilot where cohort = 'au-top-2026-10-12') <> 50 then raise exception 'v2.15.262 post-check: cohort is not 50'; end if;
  if (select count(*) from pipeline.onboarding_pilot m where m.cohort = 'au-top-2026-10-12'
        and not exists (select 1 from pipeline.provider_onboarding o where o.provider_id = m.provider_id)) > 0 then raise exception 'v2.15.262 post-check: member without an onboarding row'; end if;
end $chk$;
