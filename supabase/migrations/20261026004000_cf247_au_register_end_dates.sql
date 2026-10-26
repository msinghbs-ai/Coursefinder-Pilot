-- CF-247 AU completion week, step 1 (Platform Admin 26 Oct 2026 17:01: "Register-sync fix: CRICOS end dates recorded so deregistered is
-- separable from current. Small build, own PR."). Record: admin docs/platform/ui-audit/2026-10-26-au-completion-week.md section 4.
--
-- Found 26 Oct 17:2x: the 30 Sep CRICOS edition (still the publisher's current file; source check 25 Oct 23:41 UTC, hash unchanged) left
-- 563 course codes off the register, but nothing records an end date: every CRICOS provider registration reads 'active' with no valid_to,
-- so a deregistered provider cannot be told from a current one. The 563 courses' retirement is held for a Platform Admin approval
-- (run b8a541af, over the automatic limit) and is not touched here.
--
-- 1 security.layer1_register_end_dates_v1(source): from the latest planned register edition of a seen-tracked-by-plan source (CRICOS):
--   - a course registration whose code is not in the edition gets valid_to = the last date an edition listed it (CRICOS publishes no
--     end date; where earlier editions were not tracked, the date a register run found it gone). Listed again: valid_to cleared.
--   - a provider registration none of whose courses is in the edition is 'ended', valid_to = the latest of its courses' end dates;
--     a course listed again restores it ('active', valid_to cleared). The mirror trigger copies the dates to provider_identifiers.
--   - guard: nothing is ended when the edition lists less than layer1.register_end_dates_min_share of the tracked course codes.
--   - every run is recorded in pipeline.register_end_date_runs.
-- 2 security.au_publish_eligibility_v1(): read-only. For each unpublished active AU provider: eligible to publish when its CRICOS
--   registration is current with at least publish.eligible_min_current_courses courses on the edition and its site answers
--   (provider discovery mapped, at least publish.eligible_min_site_pages course pages kept); otherwise a named cause and owner.
-- 3 job layer1-register-end-dates (daily 04:41 UTC, catalogued) while layer1.register_end_dates_on is 1.
-- Consumer API: shape untouched. Zoho reads the CRICOS code from provider_registrations and orders by status only among
-- inactive / cancelled / archived; 'ended' is outside that list, so its output does not change. Course lifecycle is not changed.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'layer1.register_end_dates_on', 'Register end dates: on', '1: job layer1-register-end-dates records the end date of every CRICOS course and provider registration that is no longer on the latest register edition, and restores any that come back. 0: nothing is recorded.', 'number', '1'::jsonb, 0, 1, 'on/off', 950, 'Register', 'security.layer1_register_end_dates_v1, job layer1-register-end-dates', 'CF-247 AU completion week, Platform Admin 26 Oct 2026 17:01 (register-sync fix)'),
 ('pipeline', 'layer1.register_end_dates_min_share', 'Register end dates: edition must list at least', 'Safety guard: when the latest register edition lists less than this share of the tracked course codes (a truncated or partial file), no registration is ended.', 'number', '0.9'::jsonb, 0.5, 1, 'share', 951, 'Register', 'security.layer1_register_end_dates_v1', 'CF-247 AU completion week, Platform Admin 26 Oct 2026 17:01'),
 ('pipeline', 'publish.eligible_min_current_courses', 'Publish eligibility: courses on the register at least', 'An unpublished provider is eligible to publish only when at least this many of its courses are on the latest register edition.', 'number', '1'::jsonb, 1, 50, 'courses', 952, 'Register', 'security.au_publish_eligibility_v1', 'CF-247 AU completion week, Platform Admin 26 Oct 2026 17:01 ("registered + live site → publish")'),
 ('pipeline', 'publish.eligible_min_site_pages', 'Publish eligibility: course pages found at least', 'An unpublished provider is eligible to publish only when its site answered and at least this many course pages were kept from it.', 'number', '1'::jsonb, 1, 50, 'pages', 953, 'Register', 'security.au_publish_eligibility_v1', 'CF-247 AU completion week, Platform Admin 26 Oct 2026 17:01 ("registered + live site → publish")')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.register_end_date_runs (
  id bigint generated always as identity primary key,
  source_id uuid not null,
  edition_run_id uuid,
  edition_at timestamptz,
  listed int,
  tracked int,
  status text not null check (status in ('applied', 'guarded', 'off', 'no_edition')),
  courses_ended int not null default 0,
  courses_restored int not null default 0,
  providers_ended int not null default 0,
  providers_restored int not null default 0,
  detail jsonb not null default '{}'::jsonb,
  ran_at timestamptz not null default now()
);
comment on table pipeline.register_end_date_runs is 'CF-247 AU completion week (Platform Admin 26 Oct 2026 17:01): each run of security.layer1_register_end_dates_v1 — the register edition used, the guard, and the course and provider registrations ended or restored';

create or replace function security.layer1_register_end_dates_v1(p_source_id uuid default 'b5680d74-49c5-49a5-b198-a625f3e3fdcf')
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_plan pipeline.layer1_run_plans; v_scheme text; v_listed int; v_tracked int; v_ce int := 0; v_cr int := 0; v_pe int := 0; v_pr int := 0;
        v_status text; v_share numeric := security.pipeline_num_v1('layer1.register_end_dates_min_share', 0.9);
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
  select count(*) filter (where s.seen_at >= v_plan.created_at), count(*) into v_listed, v_tracked
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
  )
  update catalogue.course_registrations cr set valid_to = g.d from gone g
   where cr.id = g.id and g.d is not null
     -- a tracked last-listed date always wins; the fallback (date found gone) only fills an empty end date, so a later retirement
     -- (which clears the register row state) never moves a recorded date
     and (cr.valid_to is null or (g.tracked and cr.valid_to is distinct from g.d));
  get diagnostics v_ce = row_count;
  -- courses listed again
  update catalogue.course_registrations cr set valid_to = null
    from pipeline.layer1_register_row_state s
   where lower(cr.scheme) = v_scheme and cr.valid_to is not null
     and s.source_id = p_source_id and s.record_key = upper(cr.registration_code) and s.seen_at >= v_plan.created_at;
  get diagnostics v_cr = row_count;

  -- providers: none of their courses listed -> ended; any listed -> current
  with pv as (
    select pr.id, count(*) filter (where s.seen_at >= v_plan.created_at) listed, max(cr.valid_to) last_listed
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
      join pipeline.layer1_register_row_state s on s.source_id = p_source_id and s.record_key = upper(cr.registration_code) and s.seen_at >= v_plan.created_at
     where pr.source_id = p_source_id and lower(pr.registration_scheme) = v_scheme and (pr.status = 'ended' or pr.valid_to is not null)
     group by pr.id
  ), r as (
    update catalogue.provider_registrations pr set status = 'active', valid_to = null, checked_at = v_plan.created_at
      from pv where pr.id = pv.id returning 1
  )
  select count(*) into v_pr from r;

  insert into pipeline.register_end_date_runs(source_id, edition_run_id, edition_at, listed, tracked, status, courses_ended, courses_restored, providers_ended, providers_restored)
  values (p_source_id, v_plan.run_id, v_plan.created_at, v_listed, v_tracked, 'applied', v_ce, v_cr, v_pe, v_pr);
  return jsonb_build_object('status', 'applied', 'edition', v_plan.run_id, 'edition_at', v_plan.created_at, 'listed', v_listed, 'tracked', v_tracked,
                            'courses_ended', v_ce, 'courses_restored', v_cr, 'providers_ended', v_pe, 'providers_restored', v_pr);
end $f$;
comment on function security.layer1_register_end_dates_v1(uuid) is 'CF-247 AU completion week (Platform Admin 26 Oct 2026 17:01): records the end date of CRICOS course and provider registrations no longer on the latest register edition (and restores any listed again); guarded by layer1.register_end_dates_min_share';

create or replace function security.au_publish_eligibility_v1()
returns table(provider_id uuid, provider_name text, provider_type text, cricos_code text, registration_status text, registration_valid_to date,
              courses_active int, courses_listed int, courses_not_listed int, site_status text, site_pages_kept int, site_mapped_at timestamptz,
              website text, verdict text, cause text, owner text)
language sql stable security definer set search_path = '' as $f$
  with ed as (
    select p.created_at from pipeline.layer1_run_plans p
     where p.source_id = 'b5680d74-49c5-49a5-b198-a625f3e3fdcf' and p.course_hash is distinct from 'seen-tracking'
     order by p.created_at desc limit 1
  ), pv as (
    select p.id, coalesce(nullif(p.display_name, ''), p.canonical_name) nm, t.code ptype, p.website,
           (select upper(pr.registration_code) from catalogue.provider_registrations pr where pr.provider_id = p.id and lower(pr.registration_scheme) = 'cricos' order by pr.checked_at desc nulls last limit 1) code,
           (select pr.status from catalogue.provider_registrations pr where pr.provider_id = p.id and lower(pr.registration_scheme) = 'cricos' order by (pr.status = 'ended'), pr.checked_at desc nulls last limit 1) rstatus,
           (select max(pr.valid_to) from catalogue.provider_registrations pr where pr.provider_id = p.id and lower(pr.registration_scheme) = 'cricos' and pr.status = 'ended') rvalid_to,
           count(c.id)::int act,
           count(c.id) filter (where s.seen_at >= (select created_at from ed))::int listed
      from catalogue.providers p
      join ref.countries k on k.id = p.country_id and k.iso_alpha2 = 'AU'
      left join ref.provider_types t on t.id = p.provider_type_id
      left join catalogue.courses c on c.provider_id = p.id and c.lifecycle_status = 'active'
      left join catalogue.course_registrations cr on cr.course_id = c.id and lower(cr.scheme) = 'cricos'
      left join pipeline.layer1_register_row_state s on s.source_id = 'b5680d74-49c5-49a5-b198-a625f3e3fdcf' and s.record_key = upper(cr.registration_code)
     where p.publication_status = 'unpublished' and p.lifecycle_status = 'active'
     group by p.id, t.code
  )
  select pv.id, pv.nm, pv.ptype, pv.code, coalesce(pv.rstatus, 'none'), pv.rvalid_to, pv.act, pv.listed, pv.act - pv.listed,
         coalesce(d.status, 'not_checked'), coalesce(d.kept_count, 0), d.mapped_at, pv.website,
         case when coalesce(pv.rstatus, '') = 'ended' or pv.listed < security.pipeline_num_v1('publish.eligible_min_current_courses', 1) then 'hold'
              when d.status = 'mapped' and coalesce(d.kept_count, 0) >= security.pipeline_num_v1('publish.eligible_min_site_pages', 1) then 'publish'
              else 'hold' end,
         case when coalesce(pv.rstatus, '') = 'ended' then 'CRICOS registration ended (no course on the register since ' || coalesce(to_char(pv.rvalid_to, 'DD Mon YYYY'), '?') || ')'
              when pv.listed < security.pipeline_num_v1('publish.eligible_min_current_courses', 1) then 'no course on the current register edition'
              when d.status = 'mapped' and coalesce(d.kept_count, 0) >= security.pipeline_num_v1('publish.eligible_min_site_pages', 1) then 'registered and site answers'
              when d.status = 'mapped' then 'site answered but no course page kept'
              when d.status = 'failed' then 'site gave no course pages'
              when d.status = 'no_website' then 'no website on record'
              else 'site not checked yet' end,
         case when coalesce(pv.rstatus, '') = 'ended' or pv.listed < security.pipeline_num_v1('publish.eligible_min_current_courses', 1) then 'Register (Layer 1): nothing to publish'
              when d.status = 'mapped' and coalesce(d.kept_count, 0) >= security.pipeline_num_v1('publish.eligible_min_site_pages', 1) then 'Platform Admin: publish paste'
              when d.status = 'failed' or d.status = 'mapped' then 'Discovery review (site check)'
              when d.status = 'no_website' then 'Website check (find the provider''s site)'
              else 'Discovery (site not checked yet)' end
    from pv left join pipeline.coverage_provider_discovery d on d.provider_id = pv.id
$f$;
comment on function security.au_publish_eligibility_v1() is 'CF-247 AU completion week (Platform Admin 26 Oct 2026 17:01): read-only; each unpublished active AU provider, eligible to publish (CRICOS registration current with courses on the register edition, and its site answers) or held with a named cause and owner';

revoke all on function security.layer1_register_end_dates_v1(uuid) from public, anon, authenticated;
revoke all on function security.au_publish_eligibility_v1() from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('layer1-register-end-dates', 'Layer 1 register', 38, 'Register end dates (CRICOS)',
  'Daily at 04:41 UTC, while Register end dates: on is 1: from the latest CRICOS register edition, records the end date of every course registration no longer listed (the last date an edition listed it) and marks a provider registration ended when none of its courses is listed; any listed again is restored. Nothing is ended when the edition lists less than the set share of the tracked course codes. Course retirement is not changed (that stays a Platform Admin approval). Every run is recorded.',
  6, false, null)
on conflict (jobname) do nothing;
select cron.schedule('layer1-register-end-dates', '41 4 * * *', $$select security.layer1_register_end_dates_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('job', 'layer1-register-end-dates', 'Layer 1', 'AU week step 1: daily register end dates', 'active', '{}', '20261026004000'),
 ('table', 'pipeline.register_end_date_runs', 'Layer 1', 'AU week step 1: each register end-date run with its guard and counts', 'active', '{}', '20261026004000'),
 ('function', 'security.layer1_register_end_dates_v1', 'Layer 1', 'AU week step 1: CRICOS course and provider registration end dates (job layer1-register-end-dates)', 'active', '{}', '20261026004000'),
 ('function', 'security.au_publish_eligibility_v1', 'Layer 1', 'AU week step 2: unpublished AU providers, eligible to publish or held with cause and owner', 'active', '{}', '20261026004000')
on conflict do nothing;

-- first run now (idempotent; the job repeats it daily)
select security.layer1_register_end_dates_v1();
