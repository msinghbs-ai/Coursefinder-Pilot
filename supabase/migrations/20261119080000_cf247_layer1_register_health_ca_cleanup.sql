-- CF-247 s714: Layer 1 Register health (ABS, BOM), stale Canadian college rows, Ontario APS, and the first LIN 19/198 run (S2-Build; Platform
-- Admin 19 Nov 2026 06:45 and 06:50: "Sync Last run (19 Nov 2026) and Next scheduled run (19 Dec 2026) on ABS Regional Population and BOM Climate
-- Statistics (IDCJCM0037) so both show Healthy, and archive/retire the 10 stale August 2026 Canadian per-college scrape rows cluttering Needs
-- attention"; "repair or pause Ontario public college programmes / APS with a clear reason").
--
-- What was read live (19 Nov 2026 07:20 AEDT):
--   * ABS Regional Population and BOM Climate Statistics have published editions (102 and 40 rows) loaded before they were Layer 1 sources;
--     their Layer 1 rows were never run (verification unverified, no hash, next run 1 and 2 Dec 2026), so the screen shows Needs attention.
--     Their loaders keep every approved or published value ("never changed by a load"), and an unchanged ABS workbook reuses its evidence.
--   * Ten Canadian college readers from 13-16 Aug 2026 (Fanshawe, Seneca, Fleming, Lambton, St. Clair, Collège Boréal, Sault, Northern,
--     Centennial, St. Lawrence) are on Manual (automatic loading off) with failed count checks (one to four programmes off the expected count).
--     Each still has no other path: 0 coverage-sweep course pages and 0 active courses (their 1,132 courses inactive since Aug 2026). On 18 Nov
--     they were kept as a genuine gap; on 19 Nov the Platform Admin asked for them to be retired.
--   * Ontario public college programmes / APS failed on 8 Nov 2026: the scoped apply timed out (statement timeout after 5 retries). It holds
--     138 course pages and 40 active courses.
-- What it changes (data in existing tables only; no new table or function; G3 75/48):
--   1. ABS and BOM are due now: the standard Layer 1 scheduler (hourly at :05) runs each once (download, Storage artifact, evidence record,
--      verification), which sets Last run and Healthy; the next run is one cadence (30 days) later, 19 Dec 2026. No value is overwritten.
--   2. The ten college readers are retired (source status retired, paused, automatic loading off; kept, not deleted, so any one can be restored):
--      the retired reason records that nothing replaces them yet (0 course pages, 0 active courses), so the gap stays on record.
--   3. Ontario APS is paused with its reason (the scoped apply times out; repair: batch the apply), until the apply is batched.
--   4. LIN 19/198 (registered in 20261119075000) is due now, so its first read (with the Home Affairs pages, loader v1.5.0) runs through the
--      standard Layer 1 scheduler.
-- Nothing is dropped or deleted. Each retire, pause and due is written to pipeline.admin_control_events.
-- Replaces: nothing.
-- Retires: the ten Canadian college readers named above (Layer 1 sources; retired, not dropped).

-- 1. ABS and BOM due now
update pipeline.layer1_source_operations o
   set next_verification_at = now(), updated_at = now(),
       change_reason = 'Due 19 Nov 2026 (20261119080000, s714): first run through the standard Layer 1 scheduler; editions loaded before registration'
  from pipeline.sources s
 where s.id = o.source_id and s.metadata->>'source_system' = 'DESTINATION'
   and s.label in ('ABS Regional Population', 'BOM Climate Statistics (IDCJCM0037)') and o.active and not o.paused and o.last_verified_at is null;

-- 2. the ten Canadian college readers, retired with the gap on record
do $r$
declare r record; v_n int := 0;
begin
  for r in
    select s.id, s.label, (select count(*) from pipeline.coverage_course_pages x where x.provider_id = pv.provider_id) pages,
           (select count(*) from catalogue.courses c where c.provider_id = pv.provider_id and c.lifecycle_status = 'active') active_courses,
           (select count(*) from catalogue.courses c where c.provider_id = pv.provider_id) courses
      from pipeline.sources s
      join ref.countries co on co.id = s.country_id and co.iso_alpha2 = 'CA'
      left join lateral (select c.provider_id from catalogue.courses c where c.canonical_source_id = s.id group by c.provider_id order by count(*) desc limit 1) pv on true
     where s.label in ('Fanshawe College current programme catalogue', 'Seneca Polytechnic current academic catalogue', 'Fleming College Programs A-Z',
                       'Lambton College Full-Time Programs', 'St. Clair College Programs', 'Collège Boréal postsecondary programmes', 'Sault College Programs A-Z',
                       'Northern College programme catalogue', 'Centennial College Program Catalogue API', 'St. Lawrence College Full-Time Programs')
       and s.status <> 'retired'
  loop
    update pipeline.sources set status = 'retired',
           metadata = metadata || jsonb_build_object('retired_at', now(), 'replaced_by', null,
             'retired_reason', 'Retired on Platform Admin instruction (19 Nov 2026 06:50): August 2026 per-college reader on Manual with a failed count check. Nothing replaces it yet ('
               || r.pages || ' coverage-sweep course pages, ' || r.active_courses || ' active of ' || r.courses || ' courses); restore it or onboard the provider through coverage-sweep to close the gap.')
     where id = r.id;
    update pipeline.layer1_source_operations set paused = true, auto_ingest = false, updated_at = now(),
           change_reason = 'Retired 19 Nov 2026 (Platform Admin 06:50, s714): stale August 2026 per-college reader; no replacement yet (gap on record)'
     where source_id = r.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer1', 'source_retire', r.id::text, jsonb_build_object('label', r.label, 'replaced_by', null, 'course_pages', r.pages, 'active_courses', r.active_courses,
            'courses', r.courses, 'reason', 'Platform Admin 19 Nov 2026 06:50: archive/retire the stale August 2026 Canadian per-college rows'), null);
    v_n := v_n + 1;
  end loop;
  raise notice 'retired % Canadian college readers', v_n;
end $r$;

-- 3. Ontario APS paused with its reason
update pipeline.layer1_source_operations o
   set paused = true, updated_at = now(),
       change_reason = 'Paused 19 Nov 2026 (Platform Admin 06:45, s714): the scoped apply timed out on 8 Nov 2026 (statement timeout after 5 retries); '
                    || 'repair: batch svc_layer1_apply_scoped_course_records for this source, then resume. 138 course pages and 40 active courses stay as they are.'
  from pipeline.sources s
 where s.id = o.source_id and s.label = 'Ontario public college programmes / APS' and not o.paused;
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'layer1', 'source_pause', s.id::text, jsonb_build_object('label', s.label, 'reason', 'scoped apply timed out 8 Nov 2026; batch the apply, then resume'), null
  from pipeline.sources s where s.label = 'Ontario public college programmes / APS';

-- 4. LIN 19/198 due now (registered in 20261119075000; loader v1.5.0 deployed with it)
update pipeline.layer1_source_operations o
   set next_verification_at = now(), updated_at = now(),
       change_reason = 'Due 19 Nov 2026 (20261119080000, s714): first read through the standard Layer 1 scheduler'
  from pipeline.sources s
 where s.id = o.source_id and s.label = 'LIN 19/198 Evidence of Financial Capacity (Subclass 500 and 590)' and o.last_verified_at is null;

-- post-checks (rolled back with the dry run if any fails)
do $chk$
declare v_n int; v_drift jsonb;
begin
  select count(*) into v_n from pipeline.sources s join ref.countries c on c.id = s.country_id
   where c.iso_alpha2 = 'CA' and s.status = 'retired' and s.metadata->>'retired_reason' like 'Retired on Platform Admin instruction (19 Nov 2026 06:50)%';
  if v_n <> 10 then raise exception 'post-check: expected 10 retired Canadian readers, found %', v_n; end if;
  select count(*) into v_n from pipeline.layer1_source_operations o join pipeline.sources s on s.id = o.source_id
   where s.label in ('ABS Regional Population', 'BOM Climate Statistics (IDCJCM0037)') and o.next_verification_at <= now() and o.active and not o.paused;
  if v_n <> 2 then raise exception 'post-check: ABS and BOM are not both due (%)', v_n; end if;
  if not exists (select 1 from pipeline.layer1_source_operations o join pipeline.sources s on s.id = o.source_id
                  where s.label = 'Ontario public college programmes / APS' and o.paused) then
    raise exception 'post-check: Ontario APS is not paused';
  end if;
  v_drift := security.consumer_api_check_v1();
  if jsonb_typeof(v_drift) = 'array' then
    if jsonb_array_length(v_drift) > 0 then raise exception 'consumer API drift %', v_drift; end if;
  elsif jsonb_array_length(coalesce(v_drift->'drift', '[]'::jsonb)) > 0 then raise exception 'consumer API drift %', v_drift->'drift';
  end if;
end $chk$;
