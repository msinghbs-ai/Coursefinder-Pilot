-- CF-247 (Decision 210): an approved fee schedule settles flagged fees, so a person does not check the same fee twice.
-- Reported 1 Oct 2026 23:43 (Platform Admin): Layer 4 › Flagged values still asks a person to confirm "per year" fees
-- (486 open) for universities whose fee schedule was already approved. Measured: Charles Sturt 8 flagged fees equal
-- the approved 2027 schedule and 17 more are about 4% lower (last year's fee); first run settles 30.
-- The flag's question is the period: per year or whole course. An approved schedule answers it:
--   * the same amount, per year, for the same course (CRICOS code) -> confirmed by the fee schedule;
--   * a per-year amount within 15% of the flagged fee -> the flagged fee is per year too (a whole-course fee would be
--     about two or more times larger) -> the period is confirmed; the amount stays as recorded (each year is kept as
--     its own record in the queued per-year change);
--   * anything else stays open, with the schedule's fee shown beside it (Layer 4 › Flagged values).
-- Runs when a schedule is approved and once now for the schedules already approved. Values entered by hand are never
-- changed (only the flag and the fee's notes and verified time are updated). Unread fee documents of universities with
-- open flags are read first.

create or replace function security.fee_schedule_settle_flags_v1(p_source_id uuid default null) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare r record; v_same int := 0; v_period int := 0; v_courses uuid[] := '{}';
begin
  for r in
    with sched as (
      select fr.provider_id, fr.course_code, fr.amount, fr.fee_year, s.id source_id,
             min(fr.amount) over (partition by fr.source_id, fr.course_code) amin, max(fr.amount) over (partition by fr.source_id, fr.course_code) amax,
             row_number() over (partition by fr.provider_id, fr.course_code order by fr.fee_year desc nulls last, s.decided_at desc) pick
        from pipeline.provider_fee_rows fr join pipeline.provider_fact_sources s on s.id = fr.source_id
       where s.decision = 'approved' and fr.current and fr.basis = 'annual' and (p_source_id is null or s.id = p_source_id))
    select f.id flag_id, f.entity_id course_id, fe.id fee_id, fe.amount, sc.amount sched_amount, sc.fee_year, sc.source_id
      from pipeline.data_flags f
      join catalogue.course_fees fe on fe.id = f.record_id and fe.status = 'active'
      join catalogue.courses c on c.id = f.entity_id
      join sched sc on sc.provider_id = c.provider_id and sc.course_code = upper(btrim(c.course_code)) and sc.pick = 1 and sc.amin = sc.amax
     where f.status = 'open' and f.flag_code = 'tuition_period_assumed_annual'
     for update of f
  loop
   begin
    if r.amount = r.sched_amount then
      update catalogue.course_fees set fee_year = coalesce(fee_year, r.fee_year), last_verified_at = now(), updated_at = now(),
             notes = coalesce(notes, '') || format(' | per year confirmed by the approved fee schedule (%s) %s', coalesce(r.fee_year::text, 'year not stated'), to_char(now(), 'DD Mon YYYY'))
       where id = r.fee_id;
      update pipeline.data_flags set status = 'confirmed', resolved_at = now(),
             resolution = jsonb_build_object('action', 'confirmed_by_fee_schedule', 'source_id', r.source_id, 'fee_year', r.fee_year, 'schedule_amount', r.sched_amount)
       where id = r.flag_id;
      v_same := v_same + 1; v_courses := v_courses || r.course_id;
    elsif r.amount > 0 and r.sched_amount / r.amount between 0.85 and 1.15 then
      update catalogue.course_fees set last_verified_at = now(), updated_at = now(),
             notes = coalesce(notes, '') || format(' | per year supported by the approved fee schedule (%s a year in %s) %s', r.sched_amount, coalesce(r.fee_year::text, 'year not stated'), to_char(now(), 'DD Mon YYYY'))
       where id = r.fee_id;
      update pipeline.data_flags set status = 'confirmed', resolved_at = now(),
             resolution = jsonb_build_object('action', 'period_confirmed_by_fee_schedule', 'source_id', r.source_id, 'fee_year', r.fee_year, 'schedule_amount', r.sched_amount)
       where id = r.flag_id;
      v_period := v_period + 1; v_courses := v_courses || r.course_id;
    end if;
   exception when others then null; -- a value locked by hand is left for a person
   end;
  end loop;
  if cardinality(v_courses) > 0 then perform search.refresh_course_enrichment_scoped_v1(v_courses, true); end if;
  return jsonb_build_object('confirmed_same_fee', v_same, 'confirmed_period', v_period);
end $fn$;
revoke all on function security.fee_schedule_settle_flags_v1(uuid) from public, anon, authenticated;

-- Approval settles the flags it answers.
do $d$
declare s text; d text; v text;
  o text := E'  v_sum := coalesce(v_sum, ''{}''::jsonb) || jsonb_build_object(''written'', v_n, ''refused'', v_err);\n';
  n text := E'  v_sum := coalesce(v_sum, ''{}''::jsonb) || jsonb_build_object(''written'', v_n, ''refused'', v_err) || jsonb_build_object(''flags'', security.fee_schedule_settle_flags_v1(p_source_id));\n';
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'admin_provider_fee_schedule_decide';
  v := md5(s);
  if v is distinct from '664ed3249f3c07678db0797dc18c4c8d' then raise exception 'admin_provider_fee_schedule_decide changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'summary line not found once'; end if;
  execute replace(d, o, n);
end $d$;

-- Flagged values show the approved schedule's fee for the course, when there is one.
do $r$
declare s text; d text; v text;
  o text := $o$'quotes',f.detail->'quotes')$o$;
  n text := $n$'quotes',f.detail->'quotes',
        'schedule',(select jsonb_build_object('amount',fr.amount,'year',fr.fee_year,'url',sr.url) from pipeline.provider_fee_rows fr join pipeline.provider_fact_sources sr on sr.id=fr.source_id
                     where sr.decision='approved' and fr.current and fr.basis='annual' and fr.provider_id=c.provider_id and fr.course_code=upper(btrim(c.course_code))
                     order by fr.fee_year desc nulls last, sr.decided_at desc limit 1))$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'admin_data_flags_read_v1';
  v := md5(s);
  if v is distinct from 'badaca6600ca02c5195491306d82440e' then raise exception 'admin_data_flags_read_v1 changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'quotes field not found once'; end if;
  execute replace(d, o, n);
end $r$;

-- Read the fee documents of universities with open flags first.
update pipeline.provider_fact_sources fs set rank = 0, updated_at = now()
 where fs.kind = 'fee_schedule' and fs.status = 'found' and fs.rank > 0
   and exists (select 1 from pipeline.data_flags f join catalogue.courses c on c.id = f.entity_id
                where f.status = 'open' and c.provider_id = fs.provider_id);

-- Settle what the schedules already approved answer.
select security.fee_schedule_settle_flags_v1(null);
