-- CF-247 Layer 1 Register: overdue "Next" dates, the "Needs attention" sources, and superseded Canadian college readers (S2-Build, Platform Admin
-- 18 Nov 2026 10:51, issues seen on v2.16.32).
--
-- What was read live (18 Nov 2026 10:55 AEDT)
--   * Eight active, unpaused sources showed a "Next" ingestion date in the past (7 to 12 Nov). The Layer 1 scheduler is driven by the
--     verification date (security.layer1_regulatory_scheduler_tick_impl); an ingestion runs when a check finds the file changed
--     (security.layer1_auto_ingest_tick_v1). Nothing moved next_ingestion_at on after a check that found the file unchanged or failed, so
--     the date stayed in the past although nothing was waiting.
--   * Seventeen unpaused sources read as needing attention: fourteen Canadian college readers written in code (verification failed: twelve on an
--     exact expected count off by 1 to 5, one on pagination, one on the college's certificate), the Ontario colleges register (last run failed
--     on a statement time-out), and the two QS ranking sources (2026: "publisher source parsed zero ranking observations"; 2027: never
--     verified), whose editions were applied from the publisher files (manual imports, 5 Sep 2026).
--   * Supersession, checked per college: the Ontario colleges register covers only Humber, George Brown, Canadore and La Cité. For Aurora
--     College, College of the North Atlantic, Confederation College and Loyalist College, coverage-sweep holds the course pages (36, 117, 59,
--     68) and keeps their active courses (11, 105, 22, 57); their code readers are superseded. The other ten Ontario colleges (Centennial,
--     Boréal, Fanshawe, Fleming, Lambton, Northern, Sault, Seneca, St. Clair, St. Lawrence) have no other path: no course pages, onboarding
--     stopped and every course inactive since 16-17 Aug 2026. Their readers are NOT retired: "Needs attention" for them is a genuine gap.
--
-- What it changes
--   1. security.layer1_next_due_roll_v1, a live target of the unified dispatcher (rollup-scheduler, pipeline.rollup_targets, hourly at :23):
--      moves an overdue next_ingestion_at of an active, unpaused, unretired source on by whole ingestion cadences to its next date after now,
--      when no run of the source is queued or running. Run once by this migration. Logged in pipeline.admin_control_events.
--   2. The four superseded readers are retired (source status retired, paused, automatic ingestion off; kept, not deleted), each checked here
--      to still have coverage-sweep course pages and active courses; their dedicated edge functions are marked retiring in
--      pipeline.component_register (replaced by coverage-sweep, retire after 14 days). The shared layer1-ca-firstparty-catalogues stays.
--   3. The QS 2026 and 2027 sources: verification recorded as passed where an applied publisher-file import of that system and edition
--      exists, with a message that says so; the automatic publisher read is not used for these editions.
-- Nothing is dropped or deleted. No course or provider is changed. G3 untouched.
-- Replaces: nothing (overdue next_ingestion_at had no roll-forward).
-- Retires: the Layer 1 sources "Aurora College academic programmes", "College of the North Atlantic programme guide", "Confederation College
--          full-time programme API", "Loyalist College programme directory"; edge functions layer1-ca-cna-programs,
--          layer1-ca-confederation-programs, layer1-ca-loyalist-programs (retiring; replaced by coverage-sweep).

-- 1. the roll-forward
create or replace function security.layer1_next_due_roll_v1()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_n int := 0; v_ids jsonb;
begin
  with due as (
    select o.source_id, o.next_ingestion_at old_at,
           o.next_ingestion_at + make_interval(days => coalesce(nullif(o.ingestion_cadence_days, 0), 30)  -- fixed: a source with no cadence rolls by a month, the register default
                                * (floor(extract(epoch from now() - o.next_ingestion_at) / (86400.0 * coalesce(nullif(o.ingestion_cadence_days, 0), 30)))::int + 1)) new_at  -- fixed: a day in seconds
      from pipeline.layer1_source_operations o join pipeline.sources s on s.id = o.source_id
     where o.active and not o.paused and s.status <> 'retired' and o.next_ingestion_at < now()
       and not exists (select 1 from pipeline.layer1_run_queue q where q.source_id = o.source_id and q.status in ('queued', 'running'))
     for update of o skip locked),
  upd as (update pipeline.layer1_source_operations o set next_ingestion_at = d.new_at, updated_at = now()
            from due d where o.source_id = d.source_id
          returning o.source_id, d.old_at, d.new_at)
  select count(*), coalesce(jsonb_agg(jsonb_build_object('source_id', source_id, 'from', old_at, 'to', new_at)), '[]'::jsonb) into v_n, v_ids from upd;
  if v_n > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer1', 'next_due_roll', 'layer1-next-due-roll', jsonb_build_object('rolled', v_n, 'sources', v_ids), null);
  end if;
  return jsonb_build_object('rolled', v_n, 'at', now());
end $function$;
comment on function security.layer1_next_due_roll_v1() is 'CF-247 (18 Nov 2026): moves an overdue next ingestion date of an active, unpaused Layer 1 source on by whole cadences when nothing of it is queued or running (target layer1-next-due-roll of rollup-scheduler).';
revoke all on function security.layer1_next_due_roll_v1() from public, anon, authenticated;

insert into pipeline.rollup_targets(target_code, legacy_job, call_sql, call_md5, schedule, rollup_group, priority, enabled, mode, expected_ms, note)
values ('layer1-next-due-roll', null, 'select security.layer1_next_due_roll_v1()', md5('select security.layer1_next_due_roll_v1()'), '23 * * * *', 'A', 60, true, 'live', 1000,
        'CF-247 18 Nov 2026 (Platform Admin 10:51): new target, no legacy job; moves overdue Layer 1 next ingestion dates on')
on conflict (target_code) do nothing;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, introduced_in)
select v.kind, v.name, 'Layer 1', 'Layer 1 register', v.purpose, 'active', '20261118125000'
  from (values
    ('function', 'security.layer1_next_due_roll_v1', 'Moves overdue Layer 1 next ingestion dates on by whole cadences (rollup-scheduler target layer1-next-due-roll, hourly at :23)')) v(kind, name, purpose)
 where not exists (select 1 from pipeline.component_register r where r.kind = v.kind and r.name = v.name);

select security.layer1_next_due_roll_v1();

-- 2. retire the four superseded Canadian college readers (checked first)
do $$
declare r record; v_n int := 0;
begin
  for r in
    select s.id, s.label, (select count(*) from pipeline.coverage_course_pages x where x.provider_id = pv.provider_id) pages,
           (select count(*) from catalogue.courses c where c.provider_id = pv.provider_id and c.lifecycle_status = 'active') active_courses
      from pipeline.sources s
      join lateral (select c.provider_id from catalogue.courses c where c.canonical_source_id = s.id group by c.provider_id order by count(*) desc limit 1) pv on true
     where s.label in ('Aurora College academic programmes', 'College of the North Atlantic programme guide', 'Confederation College full-time programme API',
                       'Loyalist College programme directory') and s.status <> 'retired'
  loop
    if r.pages = 0 or r.active_courses = 0 then
      raise exception 'source % is not superseded by coverage-sweep as read (course pages %, active courses %); not retired', r.label, r.pages, r.active_courses;
    end if;
    update pipeline.sources set status = 'retired',
           metadata = metadata || jsonb_build_object('retired_at', now(), 'replaced_by', 'coverage-sweep',
                        'retired_reason', 'Superseded by coverage-sweep course pages (' || r.pages || ' pages, ' || r.active_courses || ' active courses, 18 Nov 2026); the code reader failed verification')
     where id = r.id;
    update pipeline.layer1_source_operations set paused = true, auto_ingest = false, updated_at = now(),
           change_reason = 'Retired 18 Nov 2026 (Platform Admin 10:51): superseded by coverage-sweep'
     where source_id = r.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer1', 'source_retire', r.id::text, jsonb_build_object('label', r.label, 'replaced_by', 'coverage-sweep', 'course_pages', r.pages, 'active_courses', r.active_courses,
            'reason', 'Platform Admin 18 Nov 2026 10:51: retire legacy hardcoded rows replaced by coverage-sweep'), null);
    v_n := v_n + 1;
  end loop;
  raise notice 'retired % superseded readers', v_n;
end $$;

update pipeline.component_register set status = 'retiring', replaced_by = 'coverage-sweep', retire_after = current_date + 14  -- fixed: hygiene.retire_after_days (14) as the date written
 where kind = 'edge_function' and name in ('layer1-ca-cna-programs', 'layer1-ca-confederation-programs', 'layer1-ca-loyalist-programs') and status = 'active';

-- 3. QS editions applied from the publisher files
do $$
declare r record;
begin
  for r in
    select s.id, s.label, mi.original_filename, mi.uploaded_at, o.verification_cadence_days cad
      from pipeline.sources s join pipeline.layer1_source_operations o on o.source_id = s.id
      join ranking.systems sy on sy.code = s.metadata->>'ranking_system_code'
      join lateral (select m.original_filename, m.uploaded_at from ranking.manual_imports m
                     where m.system_id = sy.id and m.edition_year = (s.metadata->>'edition_year')::int and m.status = 'applied' order by m.uploaded_at desc limit 1) mi on true
     where s.metadata->>'dataset_class' = 'rankings' and s.metadata->>'ranking_system_code' = 'qs_wur' and s.status <> 'retired'
       and coalesce(o.verification_status, '') not in ('passed', 'warning')
  loop
    update pipeline.layer1_source_operations
       set verification_status = 'passed', last_verified_at = now(), next_verification_at = now() + make_interval(days => coalesce(r.cad, 30)),  -- fixed: the register default cadence
           verification_message = 'Edition applied from the publisher file ' || r.original_filename || ' (uploaded ' || to_char(r.uploaded_at at time zone 'Australia/Sydney', 'DD Mon YYYY') ||
                                  '); the automatic publisher read is not used for this edition.',
           updated_at = now(), change_reason = 'Reconciled 18 Nov 2026 (Platform Admin 10:51): edition applied from the publisher file'
     where source_id = r.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer1', 'source_verification_reconciled', r.id::text, jsonb_build_object('label', r.label, 'publisher_file', r.original_filename), null);
  end loop;
end $$;

-- 4. post-checks
do $$
begin
  if exists (select 1 from pipeline.layer1_source_operations o join pipeline.sources s on s.id = o.source_id
              where o.active and not o.paused and s.status <> 'retired' and o.next_ingestion_at < now()
                and not exists (select 1 from pipeline.layer1_run_queue q where q.source_id = o.source_id and q.status in ('queued', 'running'))) then
    raise exception 'post-check: an overdue next ingestion date was not moved on';
  end if;
  if (select count(*) from pipeline.sources where status = 'retired' and metadata->>'replaced_by' = 'coverage-sweep'
        and label in ('Aurora College academic programmes', 'College of the North Atlantic programme guide', 'Confederation College full-time programme API', 'Loyalist College programme directory')) <> 4 then
    raise exception 'post-check: the four superseded readers';
  end if;
  if exists (select 1 from pipeline.sources where status = 'retired' and label in ('Fanshawe College current programme catalogue', 'Seneca Polytechnic current academic catalogue')) then
    raise exception 'post-check: a reader with no other path was retired';
  end if;
  if not exists (select 1 from pipeline.rollup_targets where target_code = 'layer1-next-due-roll' and mode = 'live' and enabled and call_md5 = md5(call_sql)) then
    raise exception 'post-check: rollup target';
  end if;
end $$;
