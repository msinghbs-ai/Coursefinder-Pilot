-- CF-247 RM1A-3 (O29, F-DISC.01/.04): CRICOS registrations wrongly end-dated while their edition row waits to be applied. Admin destination
-- data design v1.4 (docs/Roadmap/2026-01/DESTINATION-DATA-DESIGN.md), Platform Admin 17 Nov 2026 06:43 AEDT (Wave 1B).
-- Found 17 Nov (read only): 2,297 active CRICOS registrations carry valid_to 1 Oct 2026. The stored 11 Nov edition (plan d35d2541) lists
--   25,199 current codes: 23,246 unchanged, 1,596 changed, 357 new, and 701 departed. security.layer1_register_end_dates_v1 counted a
--   code as listed only when its register row state was seen at or after the plan; a changed row is not seen again until its slice is
--   applied, so the 1,596 changed codes were end-dated as if gone. They are on the stored register. The 701 departed codes are not.
-- Guards: G1 (no new job; job layer1-register-end-dates unchanged), G2 (no operational value), G3 (no consumer function, table shape or
--   edge function altered; course_registrations.valid_to and provider_registrations status values are data the existing job maintains),
--   G4 (tests/uat/cf-247-rm1a3-register-end-dates-pending-contract.spec.mjs), Decision 260.
-- What:
--   1. security.layer1_register_end_dates_v1: a code the latest planned edition carries as a new or changed item is listed, exactly as
--      one seen at or after the plan. Nothing else changes: the guard, the last-listed date for departed codes, provider ended and
--      restored. No date is invented: a wrongly ended registration is restored by the function's own "listed again" step.
--   2. The function is run once here (as the daily job runs it), so the correction does not wait for 04:41 UTC. Idempotent.
--   3. security.course_recognition_v1: the held reason for an active registration with a past end date is named for what it is,
--      not_on_latest_register_edition (was registration_dates_inconsistent). recognition[] is unchanged.
--   4. security.course_recognition_delivery_v1: next action names the pending register departures approval.
-- Replaces: security.layer1_register_end_dates_v1(uuid), security.course_recognition_v1(uuid[]), security.course_recognition_delivery_v1()
--   (same names and signatures; md5-guarded against live). Retires: nothing.
-- Reversal: re-create the three functions from 20261026004000 and 20261113333000. Restored end dates return at the next daily run.

do $guard$
declare v_want jsonb := jsonb_build_object(
  'security.layer1_register_end_dates_v1(uuid)', '1d46c95fb107f8cdb4c90b321f64ded6',
  'security.course_recognition_v1(uuid[])', '9f3203c3a0d2546897c17285ccf31e28',
  'security.course_recognition_delivery_v1()', '1d28914656cfc1e3bd6d9dd7f7e60714'); k text;
begin
  for k in select jsonb_object_keys(v_want) loop
    if md5(pg_get_functiondef(k::regprocedure)) <> v_want->>k then
      raise exception 'live % differs from the definition this change replaces (md5 %)', k, md5(pg_get_functiondef(k::regprocedure));
    end if;
  end loop;
end $guard$;

-- 1 -------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.layer1_register_end_dates_v1(p_source_id uuid default 'b5680d74-49c5-49a5-b198-a625f3e3fdcf'::uuid)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_plan pipeline.layer1_run_plans; v_scheme text; v_listed int; v_tracked int; v_ce int := 0; v_cr int := 0; v_pe int := 0; v_pr int := 0;
        v_status text; v_share numeric := security.pipeline_num_v1('layer1.register_end_dates_min_share', 0.9);
        v_pending text[] := '{}';  -- RM1A-3: codes the edition lists as new or changed items, not yet applied (so not yet seen again)
begin
  if security.pipeline_num_v1('layer1.register_end_dates_on', 1) < 1 then
    insert into pipeline.register_end_date_runs(source_id, status) values (p_source_id, 'off');
    return jsonb_build_object('status', 'off');
  end if;
  select lower(pr.registration_scheme) into v_scheme from catalogue.provider_registrations pr where pr.source_id = p_source_id limit 1;
  -- the latest planned edition (plan runs fingerprint every listed course; seen-tracking rows are another path)
  select * into v_plan from pipeline.layer1_run_plans p
   where p.source_id = p_source_id and p.course_hash is distinct from 'seen-tracking'
   order by p.created_at desc limit 1;
  if v_plan.run_id is null or v_scheme is null then
    insert into pipeline.register_end_date_runs(source_id, status) values (p_source_id, 'no_edition');
    return jsonb_build_object('status', 'no_edition');
  end if;
  if jsonb_typeof(to_jsonb(v_plan.items)) = 'array' then
    v_pending := coalesce(array(select upper(i->>0) from jsonb_array_elements(to_jsonb(v_plan.items)) i
                                 where i->>0 is not null and i->>2 in ('new', 'changed')), '{}');
  end if;
  select count(*) filter (where s.seen_at >= v_plan.created_at or s.record_key = any(v_pending)), count(*) into v_listed, v_tracked
    from pipeline.layer1_register_row_state s where s.source_id = p_source_id;
  if v_tracked = 0 or v_listed::numeric / v_tracked < v_share then
    insert into pipeline.register_end_date_runs(source_id, edition_run_id, edition_at, listed, tracked, status, detail)
    values (p_source_id, v_plan.run_id, v_plan.created_at, v_listed, v_tracked, 'guarded',
            jsonb_build_object('min_share', v_share, 'message', 'the edition lists too small a share of the tracked course codes; nothing ended'));
    return jsonb_build_object('status', 'guarded', 'listed', v_listed, 'tracked', v_tracked);
  end if;

  -- courses: not listed by the edition -> valid_to = last date listed (or the date a register run found it gone)
  with gone as (
    select cr.id, s.seen_at is not null tracked, coalesce((s.seen_at at time zone 'Australia/Sydney')::date,
                           (select max(r.retired_at at time zone 'Australia/Sydney')::date from pipeline.layer1_course_retirements r where r.course_id = cr.course_id)) d
      from catalogue.course_registrations cr
      join catalogue.courses c on c.id = cr.course_id
      join catalogue.providers p on p.id = c.provider_id
      join pipeline.sources so on so.id = p_source_id and so.country_id = p.country_id
      left join pipeline.layer1_register_row_state s on s.source_id = p_source_id and s.record_key = upper(cr.registration_code)
     where lower(cr.scheme) = v_scheme
       and (s.seen_at is null or s.seen_at < v_plan.created_at)
       and (s.seen_at is not null or cr.status = 'inactive')
       and upper(cr.registration_code) <> all(v_pending)
  )
  update catalogue.course_registrations cr set valid_to = g.d from gone g
   where cr.id = g.id and g.d is not null
     -- a tracked last-listed date always wins; the fallback (date found gone) only fills an empty end date, so a later retirement
     -- (which clears the register row state) never moves a recorded date
     and (cr.valid_to is null or (g.tracked and cr.valid_to is distinct from g.d));
  get diagnostics v_ce = row_count;
  -- courses listed again (seen at or after the plan, or carried by it as a new or changed item)
  update catalogue.course_registrations cr set valid_to = null
   where lower(cr.scheme) = v_scheme and cr.valid_to is not null
     and (upper(cr.registration_code) = any(v_pending)
          or exists (select 1 from pipeline.layer1_register_row_state s
                      where s.source_id = p_source_id and s.record_key = upper(cr.registration_code) and s.seen_at >= v_plan.created_at));
  get diagnostics v_cr = row_count;

  -- providers: none of their courses listed -> ended; any listed -> current
  with pv as (
    select pr.id, count(*) filter (where s.seen_at >= v_plan.created_at or upper(cr.registration_code) = any(v_pending)) listed, max(cr.valid_to) last_listed
      from catalogue.provider_registrations pr
      join catalogue.courses c on c.provider_id = pr.provider_id
      join catalogue.course_registrations cr on cr.course_id = c.id and lower(cr.scheme) = v_scheme
      left join pipeline.layer1_register_row_state s on s.source_id = p_source_id and s.record_key = upper(cr.registration_code)
     where pr.source_id = p_source_id and lower(pr.registration_scheme) = v_scheme
     group by pr.id
  ), e as (
    update catalogue.provider_registrations pr set status = 'ended', valid_to = pv.last_listed, checked_at = v_plan.created_at
      from pv where pr.id = pv.id and pv.listed = 0 and pv.last_listed is not null
       and (pr.status is distinct from 'ended' or pr.valid_to is distinct from pv.last_listed)
    returning 1
  )
  select count(*) into v_pe from e;
  with pv as (
    select pr.id
      from catalogue.provider_registrations pr
      join catalogue.courses c on c.provider_id = pr.provider_id
      join catalogue.course_registrations cr on cr.course_id = c.id and lower(cr.scheme) = v_scheme
      left join pipeline.layer1_register_row_state s on s.source_id = p_source_id and s.record_key = upper(cr.registration_code)
     where pr.source_id = p_source_id and lower(pr.registration_scheme) = v_scheme and (pr.status = 'ended' or pr.valid_to is not null)
       and (s.seen_at >= v_plan.created_at or upper(cr.registration_code) = any(v_pending))
     group by pr.id
  ), r as (
    update catalogue.provider_registrations pr set status = 'active', valid_to = null, checked_at = v_plan.created_at
      from pv where pr.id = pv.id returning 1
  )
  select count(*) into v_pr from r;

  insert into pipeline.register_end_date_runs(source_id, edition_run_id, edition_at, listed, tracked, status, courses_ended, courses_restored, providers_ended, providers_restored, detail)
  values (p_source_id, v_plan.run_id, v_plan.created_at, v_listed, v_tracked, 'applied', v_ce, v_cr, v_pe, v_pr, jsonb_build_object('pending_items', coalesce(array_length(v_pending, 1), 0)));
  return jsonb_build_object('status', 'applied', 'edition', v_plan.run_id, 'edition_at', v_plan.created_at, 'listed', v_listed, 'tracked', v_tracked,
                            'courses_ended', v_ce, 'courses_restored', v_cr, 'providers_ended', v_pe, 'providers_restored', v_pr,
                            'pending_items', coalesce(array_length(v_pending, 1), 0));
end $function$;

-- 3 -------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.course_recognition_v1(p_course_ids uuid[])
returns table (course_id uuid, recognition jsonb, held_reason text)
language sql stable security definer set search_path = '' as $$
  select u.id,
         coalesce(jsonb_agg(jsonb_build_object(
             'scheme', 'CRICOS', 'code', r.registration_code, 'status', 'registered',
             'authority', 'Australian Government (CRICOS)', 'source_url', s.url,
             'evidence_date', to_char((e.captured_at at time zone 'Australia/Melbourne')::date, 'YYYY-MM-DD'),     -- the stored register file behind this row
             'checked_on', to_char((s.last_success_at at time zone 'Australia/Melbourne')::date, 'YYYY-MM-DD'))  -- the register's last successful check
           order by r.registration_code)
           filter (where r.id is not null and s.url is not null and (r.valid_to is null or r.valid_to > current_date)), '[]'::jsonb),
         case when bool_or(r.id is not null and r.valid_to is not null and r.valid_to <= current_date) then 'not_on_latest_register_edition'
              when bool_or(r.id is not null and s.url is null) then 'registration_source_missing' end
    from unnest(p_course_ids) u(id)
    left join catalogue.course_registrations r on r.course_id = u.id and r.scheme = 'cricos' and r.status = 'active'
    left join pipeline.sources s on s.id = r.source_id and s.status = 'active'
    left join pipeline.evidence_artifacts e on e.id = r.evidence_id
   where u.id is not null
   group by u.id
$$;

-- 4 -------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.course_recognition_delivery_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v jsonb;
begin
  with d as (select d.course_id, d.country_code from search.course_documents d where d.country_code in ('AU', 'NZ')),
  x as (select d.course_id, d.country_code,
               bool_or(r.scheme = 'cricos' and s.url is not null and (r.valid_to is null or r.valid_to > current_date)) served,
               bool_or(r.scheme = 'cricos' and r.valid_to is not null and r.valid_to <= current_date) dates_bad,
               bool_or(r.scheme = 'cricos' and s.url is null) no_source,
               bool_or(r.scheme = 'nzqa') nzqa
          from d left join catalogue.course_registrations r on r.course_id = d.course_id and r.status = 'active' and r.scheme in ('cricos', 'nzqa')
          left join pipeline.sources s on s.id = r.source_id and s.status = 'active'
         group by 1, 2)
  select jsonb_build_object(
    'au', jsonb_build_object('searchable', count(*) filter (where country_code = 'AU'),
            'served', count(*) filter (where country_code = 'AU' and served),
            'held_dates_inconsistent', count(*) filter (where country_code = 'AU' and not coalesce(served, false) and dates_bad),
            'held_source_missing', count(*) filter (where country_code = 'AU' and not coalesce(served, false) and not coalesce(dates_bad, false) and no_source),
            'no_registration', count(*) filter (where country_code = 'AU' and served is null)),
    'nz', jsonb_build_object('searchable', count(*) filter (where country_code = 'NZ'),
            'with_nzqa_code', count(*) filter (where country_code = 'NZ' and nzqa),
            'served', 0, 'held_reason', 'NZQA course listing not yet captured at course grain (RM4A)'),
    'next_action', 'Held Australian courses are not on the latest CRICOS edition: Platform Admin approval of the pending register departures (Layer 1 › Sources). RM4A: capture a course-grain NZQF listing')
    into v from x;
  return v;
exception when others then
  return jsonb_build_object('known', false, 'reason', left(sqlerrm, 200));
end $f$;

-- 2 (after the functions): run once now, as the daily job does -----------------------------------------------------------------------------
select security.layer1_register_end_dates_v1();
