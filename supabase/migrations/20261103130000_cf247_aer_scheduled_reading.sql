-- CF-247 scheduled reading of academic entry requirements (AER) by eligibility rules (Platform Admin direction 3 Nov 2026 09:32, platform-led
-- enrichment: "If Claude stops working now, does StudySearch continue ..."; acceptance report 2026-11-03-platform-enrichment-control-autonomy-
-- acceptance-report.md item 4; controls audit 2026-11-03-enrichment-controls-audit.md defect 5). Workstream A.
-- Why (live, read-only, 3 Nov 2026 10:12-10:40 AEDT): no scheduled work reads AER. Course reads are queued only by security.course_entry_read_
--   enqueue_v1 from Admin screens and corrections, within a fixed list of 41 providers (entry.course_read_providers) in AU and NZ; provider matrix
--   runs have been idle since 30 Oct 07:14 within a fixed list of 33 providers (entry.providers); Canada has no AER configuration (its
--   coverage admission identities admit nothing for entry_requirements); 539 AER items wait in Layer 4 (499 course reads, 40 matrix runs).
-- What (reuses the existing enqueue, readers, gates and the D-R2 corrected-read path; no extraction logic is added or copied):
--   1. Job aer-scheduled-read (hourly at :13, created PAUSED) runs security.aer_schedule_tick_v1(). Each run, within a per-run size and a daily
--      cap (settings), and only while the AI lane enrich_fields is allowed and the OpenRouter balance stays above its floor:
--      a. HELD course reads (pending course_entry_first_read items the gate holds because the reader dropped printed requirements no waiting row
--         covers) are read again through D-R2 (security.course_entry_correction_v1, migration 20261103070000): the corrected read replaces the
--         waiting item only when complete, so no second pending item is made. Reads held only for rows a person leaves out (Approve except), for
--         rows cut at the row limit or for a shared page are not re-read (a new read of the same page cannot fix them). At most a set number of
--         tries per item, spaced by a set number of days. These run under back-pressure too: they replace items, they do not add them.
--      b. NEW course reads (security.course_entry_read_enqueue_v1, the same one-course stored-page read the Admin screens ask for) for courses
--         chosen by eligibility rules (security.aer_schedule_courses_v1) instead of a fixed list: the provider is AER-eligible
--         (security.aer_eligible_v1: country in aer.eligible_countries, active, published, enrols international students) and not hidden; its
--         country is switched on for scheduled reading (aer.schedule_countries, less aer.schedule_countries_off with the reason); the course is
--         active with a bound official page whose stored copy exists and whose identity admits entry requirements; it has no active or proposed
--         requirement, no read waiting in Layer 4, no read in progress or tried within aer.schedule_retry_days, no open "no value" hold and no
--         manual lock (aer.schedule_lock_fields). At most aer.schedule_per_provider courses of one provider a run (providers take turns; the
--         provider types in aer.priority_provider_types first). Skipped while AER items waiting in Layer 4 plus reads in progress reach
--         aer.schedule_layer4_max (back-pressure), so review is not flooded.
--      c. DUE matrix re-reads: entry pages read longer ago than entry.matrix_refresh_days are fetched again, at most batch.aer_schedule_matrix a
--         run, by the existing entry-matrix-read job and reader (AI only when the page changed). While this job is on, it owns that refresh
--         (security.entry_matrix_fire_v1 leaves it to the job) and the fixed provider list entry.providers is replaced by eligibility rules
--         (security.entry_matrix_enabled_v1: an AER-eligible provider of a switched-on country with an entry page recorded). Paused, both
--         functions behave exactly as before. Skipped under back-pressure and while the AI lane entry_matrix is stopped.
--      Each run is recorded (pipeline.aer_schedule_runs), with what it asked and why anything was skipped; held items looked at are recorded
--      (pipeline.aer_schedule_checks) so every held item is looked at in turn.
--   2. Read-only preview: security.aer_schedule_tick_v1(true) says what the next run would ask (by country and provider, held reads, matrix
--      pages, estimated US$ and Firecrawl credits) without writing; public.admin_aer_schedule (rank 4 and above) returns it with the countries
--      (on, or off with the reason, and eligible courses), the daily figures and the last runs. Shown on Catalogue › Entry requirements › Course
--      entry requirements › Course-level reading (one line).
--   3. Canada: scheduled entry reading is off for CA with the reason "no AER configuration", and one integration-queue issue is raised here
--      (fingerprint aer:country_not_configured:CA, P2, workstream A3) unless it already exists.
-- Measured on live data, read only, 3 Nov 2026 10:46 and 10:56 AEDT (the rules replicated in a SELECT; no function created): eligible for a new
--   read now AU 12,034 courses at 879 providers, NZ 151 at 40, CA 0 (off; no identity admits entry requirements there); a run at the defaults
--   asks 20 (AU 19, NZ 1); of the 499 waiting course reads, 140 are correctable by a corrected read (AU 119, NZ 21), 162 were cut at the row
--   limit, 12 share a page and 11 are claimed, locked or moved; matrix pages: the eligibility rules give 34 providers (the 33 listed and one more
--   with an entry page), and none is due before 25 Nov 2026. Expected a day at the defaults: at most 200 course reads (about US$1.22 at the
--   measured US$0.0061 a read), no Firecrawl for course reads; new reads stop once Layer 4 plus reads in progress reach 600 (539 now).
-- Settings (G2; Settings › Pipeline settings, section Entry requirements): aer.schedule_countries, aer.schedule_countries_off,
--   batch.aer_schedule_courses, aer.schedule_daily_max, batch.aer_schedule_held, aer.schedule_held_scan, aer.schedule_held_retry_days,
--   aer.schedule_held_max_tries, aer.schedule_layer4_max, aer.schedule_retry_days, aer.schedule_per_provider, aer.schedule_lock_fields,
--   batch.aer_schedule_matrix, aer.schedule_preview_rows. AI spend stays inside the existing lanes (enrich_fields, entry_matrix), their daily
--   guards and the OpenRouter floor; course reads use the stored page only (no Firecrawl); matrix pages are fetched by the existing worker within
--   the existing Firecrawl budget. No limit is raised.
-- Before (live, 3 Nov 2026 10:14 AEDT): security.entry_matrix_enabled_v1 15fc1b28e855be2d4234057527a1a086; security.entry_matrix_fire_v1
--   869da9fbdbba2a8321d3f4f3dfba2197. After: entry_matrix_enabled_v1 582a5024ffeca0ac3c5446a903b39b3f; entry_matrix_fire_v1
--   0ab725cb35f7c7d5d2309f18ec94c119 (computed on isolated fixtures loaded from the live definitions, tests/fixtures/aer-scheduled-reading; each
--   helper raises, rolling the migration back, on any difference).
-- Rollback: re-apply the two before definitions; the job stays paused; the new functions, tables and settings are then unused and go by a paste
--   file after hygiene.retire_after_days.
-- Replaces: security.entry_matrix_enabled_v1 and security.entry_matrix_fire_v1 (same names; md5-guarded edits); while job aer-scheduled-read is
--   on, the fixed provider lists entry.providers and entry.course_read_providers as the scope of automatic AER reading (eligibility rules instead)
-- Retires: nothing (the fixed lists still scope the manual "Read next batch"; nothing is left unused)
-- Nothing dropped or deleted; nothing switched on. New: two tables, seven functions, fourteen settings, one paused job, one integration issue.
--   The consumer API is not touched (G3, Decision 266): no website_*, zoho_*, api.* object or edge function changes.

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 0. the definitions the new code calls are the ones it was written against (not changed here)
do $g$
declare r record;
begin
  for r in select * from (values ('security.course_entry_read_enqueue_v1(uuid,uuid,text)', 'df0f2a2826e61b92b168847f1557435b'),
                                 ('security.course_entry_correction_v1(uuid,uuid,text)', '1e2947b30a02a38327e2b67e312339af'),
                                 ('security.course_entry_correction_check_v1(uuid,uuid,text,jsonb,jsonb)', '2e93bd9b3bc0c2ca7628f3a407b8f57f'),
                                 ('security.course_entry_gate_v1(uuid,uuid[])', '4fc06c081e451f2d0fb0a504a4fbe10f'),
                                 ('security.course_entry_cost_v1()', '3f247034427a03584856d1a5fe5dd8e1')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'live % differs from the definition this change was written against', r.sig; end if;
  end loop;
end $g$;

-- 1. settings (G2) ----------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.schedule_countries', 'Scheduled entry reading: countries switched on',
  'Countries whose courses and entry pages the scheduled entry reading (job aer-scheduled-read) may read. A country also needs AER-eligible providers (aer.eligible_countries) and an AER configuration (its course pages admit entry requirements). A country listed below as switched off is off whatever this list says.',
  'list', '["AU", "NZ"]'::jsonb, null, null, 'countries', 1040, 'Entry requirements',
  'security.aer_schedule_country_v1 (job aer-scheduled-read; security.entry_matrix_enabled_v1 while the job is on)', 'CF-247 scheduled AER reading (Platform Admin direction 3 Nov 2026 09:32 §7): per-country enablement'),
 ('pipeline', 'aer.schedule_countries_off', 'Scheduled entry reading: countries switched off, with the reason',
  'Country=reason pairs. Each country here is off for scheduled entry reading and the reason shows on Course-level reading. Canada has no AER configuration yet (integration queue issue aer:country_not_configured:CA).',
  'list', '["CA=no AER configuration"]'::jsonb, null, null, 'country=reason', 1041, 'Entry requirements',
  'security.aer_schedule_country_v1', 'CF-247 scheduled AER reading: Canada reported, not hidden (direction §7)'),
 ('pipeline', 'batch.aer_schedule_courses', 'Scheduled entry reading: course reads asked a run',
  'Most course reads (held reads read again plus new reads) one run of aer-scheduled-read asks for. Each is one AI read of the stored official page, inside the Enrich fields AI lane.',
  'number', to_jsonb(20), 1, 200, 'courses', 1042, 'Entry requirements', 'security.aer_schedule_tick_v1 (job aer-scheduled-read)', 'CF-247 scheduled AER reading: bounded runs'),
 ('pipeline', 'aer.schedule_daily_max', 'Scheduled entry reading: course reads a day at most',
  'Most course reads the scheduled entry reading asks for in any 24 hours (held reads read again plus new reads). Manual batches are not counted.',
  'number', to_jsonb(200), 0, 5000, 'courses a day', 1043, 'Entry requirements', 'security.aer_schedule_tick_v1', 'CF-247 scheduled AER reading: daily cap'),
 ('pipeline', 'batch.aer_schedule_held', 'Scheduled entry reading: held reads read again a run',
  'Most waiting course reads held as incomplete (printed requirements dropped that no row covers) that one run reads again through the corrected-read path (D-R2). Counted inside the course reads a run.',
  'number', to_jsonb(10), 0, 100, 'reads', 1044, 'Entry requirements', 'security.aer_schedule_tick_v1', 'CF-247 scheduled AER reading (b): held reads through D-R2'),
 ('pipeline', 'aer.schedule_held_scan', 'Scheduled entry reading: waiting reads checked a run',
  'How many waiting course reads one run checks against the completeness gate to find held ones to read again; the ones checked longest ago come first, so every waiting read is checked in turn.',
  'number', to_jsonb(40), 1, 500, 'reads', 1045, 'Entry requirements', 'security.aer_schedule_held_v1', 'CF-247 scheduled AER reading: the gate is checked on a bounded window'),
 ('pipeline', 'aer.schedule_held_retry_days', 'Scheduled entry reading: read a held read again after',
  'A held read whose corrected read was asked (and refused or still incomplete) is not asked again for this many days.',
  'number', to_jsonb(14), 1, 180, 'days', 1046, 'Entry requirements', 'security.aer_schedule_held_v1', 'CF-247 scheduled AER reading: spaced retries'),
 ('pipeline', 'aer.schedule_held_max_tries', 'Scheduled entry reading: corrected reads asked for one held read at most',
  'After this many corrected reads of one waiting read, the scheduled reading leaves it for a person (reject, or Approve except).',
  'number', to_jsonb(2), 1, 10, 'tries', 1047, 'Entry requirements', 'security.aer_schedule_held_v1', 'CF-247 scheduled AER reading: bounded retries'),
 ('pipeline', 'aer.schedule_layer4_max', 'Scheduled entry reading: stop new reads while Layer 4 holds',
  'New course reads and matrix re-reads are not asked while AER items waiting in Layer 4 (course reads and matrix runs) plus course reads in progress reach this number, so review is not flooded. Held reads are still read again: they replace a waiting item.',
  'number', to_jsonb(600), 0, 10000, 'items', 1048, 'Entry requirements', 'security.aer_schedule_tick_v1', 'CF-247 scheduled AER reading: back-pressure from Layer 4'),
 ('pipeline', 'aer.schedule_retry_days', 'Scheduled entry reading: read a course again after',
  'A course whose last entry read kept nothing, failed or was rejected is read again by the schedule after this many days (a course with a requirement, or one waiting in Layer 4, is not read).',
  'number', to_jsonb(30), 1, 365, 'days', 1049, 'Entry requirements', 'security.aer_schedule_courses_v1', 'CF-247 scheduled AER reading: not recently read'),
 ('pipeline', 'aer.schedule_per_provider', 'Scheduled entry reading: courses of one provider a run',
  'Most new course reads of one provider in one run; providers take turns.', 'number', to_jsonb(5), 1, 200, 'courses', 1050, 'Entry requirements',
  'security.aer_schedule_courses_v1', 'CF-247 scheduled AER reading: spread across providers'),
 ('pipeline', 'aer.schedule_lock_fields', 'Scheduled entry reading: course locks that stop a read',
  'A course with a manual lock on one of these fields (or on all fields) is not read by the schedule.', 'list', '["entry_requirements"]'::jsonb, null, null, 'fields', 1051,
  'Entry requirements', 'security.aer_schedule_courses_v1', 'CF-247 scheduled AER reading: manual locks respected'),
 ('pipeline', 'batch.aer_schedule_matrix', 'Scheduled entry reading: entry pages fetched again a run',
  'Most provider entry pages, read longer ago than Entry matrices: read again after, that one run sends to be fetched again (read again with AI only when the page changed).',
  'number', to_jsonb(4), 0, 100, 'pages', 1052, 'Entry requirements', 'security.aer_schedule_tick_v1 (security.entry_matrix_fire_v1 leaves the refresh to it while the job is on)',
  'CF-247 scheduled AER reading (a): due matrix re-reads, bounded'),
 ('pipeline', 'aer.schedule_preview_rows', 'Scheduled entry reading: providers shown in the preview',
  'Most providers listed in the preview of the next run on Course-level reading.', 'number', to_jsonb(30), 5, 200, 'providers', 1053, 'Entry requirements',
  'public.admin_aer_schedule', 'CF-247 scheduled AER reading (c): preview')
on conflict (toolset_key, key) do nothing;

-- 2. tables (additive) ------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.aer_schedule_runs(
  id bigserial primary key,
  ran_at timestamptz not null default now(),
  course_reads int not null default 0,
  corrections int not null default 0,
  matrix_pages int not null default 0,
  layer4_waiting int,
  in_progress int,
  back_pressure boolean not null default false,
  used_before int,
  room int,
  refusal text,
  estimate_usd numeric,
  detail jsonb not null default '{}'::jsonb);
comment on table pipeline.aer_schedule_runs is 'CF-247 scheduled AER reading: one row per run of job aer-scheduled-read: course reads asked (new, and held reads read again through D-R2), entry pages sent to be fetched again, Layer 4 back-pressure, the daily cap used before the run, the estimate, and why anything was skipped (detail). The daily cap is counted from these rows.';
create index if not exists aer_schedule_runs_ran_at_idx on pipeline.aer_schedule_runs(ran_at desc);
revoke all on pipeline.aer_schedule_runs from public, anon, authenticated;

create table if not exists pipeline.aer_schedule_checks(
  item_id uuid primary key,
  checked_at timestamptz not null default now(),
  outcome text not null);
comment on table pipeline.aer_schedule_checks is 'CF-247 scheduled AER reading: when job aer-scheduled-read last checked a waiting course read against the completeness gate, and what it found (held and read again, held for a person, complete, not correctable). Orders the bounded window so every waiting read is checked in turn.';
revoke all on pipeline.aer_schedule_checks from public, anon, authenticated;

-- 3. functions --------------------------------------------------------------------------------------------------------------------------
-- a country switched on for scheduled reading, or off with its reason
create or replace function security.aer_schedule_country_v1(p_country text) returns jsonb
language sql stable security definer set search_path to '' as $function$
  with o as (select btrim(split_part(x, '=', 2)) why from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'aer.schedule_countries_off'), '[]'::jsonb)) x
              where upper(btrim(split_part(x, '=', 1))) = upper(p_country) limit 1)
  select jsonb_build_object('country', upper(p_country),
           'on', coalesce(security.toolset_setting('pipeline', 'aer.schedule_countries'), '[]'::jsonb) ? upper(p_country) and not exists (select 1 from o),
           'reason', case when exists (select 1 from o) then coalesce(nullif((select why from o), ''), 'switched off')
                          when not coalesce(security.toolset_setting('pipeline', 'aer.schedule_countries'), '[]'::jsonb) ? upper(p_country) then 'not in the countries switched on' end)
$function$;
revoke all on function security.aer_schedule_country_v1(text) from public, anon, authenticated;
comment on function security.aer_schedule_country_v1(text) is 'CF-247 scheduled AER reading: is a country switched on for scheduled entry reading (aer.schedule_countries, less aer.schedule_countries_off), with the reason when off.';

-- is the scheduled reading switched on (its job active)
create or replace function security.aer_schedule_active_v1() returns boolean
language sql stable security definer set search_path to '' as $function$
  select exists (select 1 from cron.job j where j.jobname = 'aer-scheduled-read' and j.active)
$function$;
revoke all on function security.aer_schedule_active_v1() from public, anon, authenticated;
comment on function security.aer_schedule_active_v1() is 'CF-247 scheduled AER reading: true while job aer-scheduled-read is switched on. Then eligibility rules replace the fixed entry.providers list (security.entry_matrix_enabled_v1) and the job owns the due entry-page refresh (security.entry_matrix_fire_v1).';

-- the courses a scheduled run may read, by eligibility rules (p_all: every eligible course, without the per-provider turn)
create or replace function security.aer_schedule_courses_v1(p_limit int, p_all boolean default false)
returns table(course_id uuid, provider_id uuid, country text, provider_name text, tier int, turn bigint)
language sql stable security definer set search_path to '' as $function$
  with s as (select make_interval(days => security.pipeline_num_v1('aer.schedule_retry_days', 30)::int) retry,
                    coalesce(security.toolset_setting('pipeline', 'aer.schedule_lock_fields'), '[]'::jsonb) locks,
                    coalesce(security.toolset_setting('pipeline', 'aer.priority_provider_types'), '[]'::jsonb) pt,
                    security.pipeline_num_v1('aer.schedule_per_provider', 5) per),
  pv as (select e.provider_id, e.country, coalesce(p.display_name, p.short_name, p.canonical_name) pname,
                case when s.pt ? coalesce(t.code, '') then 1 else 2 end tier
           from security.aer_eligible_v1() e
           join catalogue.providers p on p.id = e.provider_id
           left join ref.provider_types t on t.id = p.provider_type_id
          cross join s
          where (security.aer_schedule_country_v1(e.country)->>'on')::boolean
            and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = e.provider_id)),
  c as (select c.id, pv.provider_id, pv.country, pv.pname, pv.tier, c.canonical_title
          from pv
          join catalogue.courses c on c.provider_id = pv.provider_id and c.lifecycle_status = 'active'
          join pipeline.coverage_course_pages g on g.course_id = c.id and g.status = 'bound'
          join pipeline.evidence_artifacts a on a.id = g.evidence_id and a.storage_path is not null
         cross join s
         where security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements')
           and not exists (select 1 from catalogue.course_entry_requirements x where x.course_id = c.id and x.status in ('active', 'proposed'))
           and not exists (select 1 from pipeline.layer4_review_items r where r.entity_id = c.id and r.field_code = 'course_entry_first_read' and r.status = 'pending')
           and not exists (select 1 from pipeline.field_enrich_items f where f.course_id = c.id and f.field = 'entry_requirements'
                             and (f.state in ('queued', 'waiting', 'ai', 'leased', 'review') or f.updated_at > now() - s.retry))
           and not exists (select 1 from pipeline.enrichment_flags fl where fl.entity = 'course' and fl.entity_key = c.id::text and fl.field = 'entry_requirements'
                             and fl.reason_code = 'enrich_no_value' and fl.state in ('raised', 'counting'))
           and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and (s.locks ? l.field or l.field = 'all'))),
  r as (select c.*, row_number() over (partition by c.provider_id order by c.canonical_title, c.id) turn from c)
  select r.id, r.provider_id, r.country, r.pname, r.tier, r.turn
    from r cross join s
   where p_all or r.turn <= s.per
   order by r.turn, r.tier, r.pname, r.provider_id
   limit p_limit
$function$;
revoke all on function security.aer_schedule_courses_v1(int, boolean) from public, anon, authenticated;
comment on function security.aer_schedule_courses_v1(int, boolean) is 'CF-247 scheduled AER reading: the courses eligible for a scheduled entry read (AER-eligible, unhidden provider of a switched-on country; active course with a bound, stored official page whose identity admits entry requirements; no requirement held, nothing waiting or in progress, not tried within aer.schedule_retry_days, no open no-value hold, no manual lock), providers taking turns. Read-only.';

-- the waiting course reads looked at this run: held as incomplete and correctable by a corrected read (eligible), or why not
create or replace function security.aer_schedule_held_v1(p_limit int)
returns table(item_id uuid, course_id uuid, provider_id uuid, country text, eligible boolean, outcome text)
language plpgsql stable security definer set search_path to '' as $function$
declare v_scan int := security.pipeline_num_v1('aer.schedule_held_scan', 40)::int;
        v_retry interval := make_interval(days => security.pipeline_num_v1('aer.schedule_held_retry_days', 14)::int);
        v_tries int := security.pipeline_num_v1('aer.schedule_held_max_tries', 2)::int;
        r record; g jsonb; v_chk jsonb; v_n int := 0;
begin
  if coalesce(p_limit, 0) <= 0 then return; end if;
  for r in select i.id, i.entity_id, c.provider_id pid, e.country cc, pg.url
             from pipeline.layer4_review_items i
             join catalogue.courses c on c.id = i.entity_id
             join security.aer_eligible_v1() e on e.provider_id = c.provider_id
             left join pipeline.coverage_course_pages pg on pg.course_id = i.entity_id
             left join pipeline.aer_schedule_checks k on k.item_id = i.id
            where i.field_code = 'course_entry_first_read' and i.status = 'pending'
              and (security.aer_schedule_country_v1(e.country)->>'on')::boolean
              and not exists (select 1 from pipeline.aer_read_supersessions s where s.old_item_id = i.id and (s.state = 'requested' or s.requested_at > now() - v_retry))
              and (select count(*) from pipeline.aer_read_supersessions s where s.old_item_id = i.id) < v_tries
            order by k.checked_at nulls first, i.created_at, i.id
            limit v_scan loop
    item_id := r.id; course_id := r.entity_id; provider_id := r.pid; country := r.cc; eligible := false;
    g := security.course_entry_gate_v1(r.id);
    if g is null or coalesce((g->>'complete')::boolean, false) then outcome := 'complete';
    elsif jsonb_array_length(coalesce(g->'shared_page', '[]'::jsonb)) > 0 then outcome := 'shared page: for a person';
    elsif coalesce((g->>'rows_cut')::int, 0) > 0 then outcome := 'cut at the row limit: for a person';
    elsif jsonb_array_length(coalesce(g->'drops_uncovered', '[]'::jsonb)) = 0 then outcome := 'held only for rows a person leaves out';
    else
      v_chk := security.course_entry_correction_check_v1(r.id, r.entity_id, r.url);
      if coalesce((v_chk->>'ok')::boolean, false) then
        if v_n < p_limit then eligible := true; outcome := 'held: read again (D-R2)'; v_n := v_n + 1; else outcome := 'held: next run'; end if;
      else outcome := left('held, not correctable: ' || coalesce(v_chk->>'why', ''), 300); end if;
    end if;
    return next;
  end loop;
end $function$;
revoke all on function security.aer_schedule_held_v1(int) from public, anon, authenticated;
comment on function security.aer_schedule_held_v1(int) is 'CF-247 scheduled AER reading: a bounded window (aer.schedule_held_scan, checked longest ago first) of waiting course reads in switched-on countries, each with the gate''s finding; eligible when held because printed requirements were dropped that no row covers and D-R2 allows a corrected read (aer.schedule_held_retry_days, aer.schedule_held_max_tries). Read-only.';

-- one run (p_preview: what the run would ask, nothing written)
create or replace function security.aer_schedule_tick_v1(p_preview boolean default false) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_batch int := security.pipeline_num_v1('batch.aer_schedule_courses', 20)::int;
        v_daymax int := security.pipeline_num_v1('aer.schedule_daily_max', 200)::int;
        v_heldmax int := security.pipeline_num_v1('batch.aer_schedule_held', 10)::int;
        v_l4max int := security.pipeline_num_v1('aer.schedule_layer4_max', 600)::int;
        v_mxmax int := security.pipeline_num_v1('batch.aer_schedule_matrix', 4)::int;
        v_cost numeric := security.course_entry_cost_v1(); v_owner uuid; v_used int; v_l4 int; v_prog int; v_bp boolean; v_room int;
        v_ai text; v_aim text; v_bal numeric; v_floor numeric; v_why text; v_reason text;
        r record; v_job uuid; v_res jsonb; v_held jsonb := '[]'::jsonb; v_new jsonb := '[]'::jsonb; v_mx jsonb := '[]'::jsonb; v_skip jsonb := '[]'::jsonb;
        v_checked jsonb := '[]'::jsonb; v_nh int := 0; v_nn int := 0; v_nm int := 0; v_fc int := 0; v_est numeric;
begin
  if not p_preview and not pg_try_advisory_xact_lock(hashtext('cf247:aer-scheduled-read')) then  -- fixed: one run at a time
    return jsonb_build_object('skipped', 'another run is in progress');
  end if;
  -- the owner the platform's standing enrichment runs as (Coverage › Attributes, Fill the gaps): course reads are asked in that name
  select c.owner into v_owner from pipeline.field_gap_queue_control c where c.id = 1;
  select coalesce(sum(x.course_reads + x.corrections), 0) into v_used from pipeline.aer_schedule_runs x
   where x.ran_at > now() - interval '1 day';  -- fixed: the daily cap is counted over the last 24 hours
  select count(*) into v_l4 from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run');
  select count(*) into v_prog from pipeline.field_enrich_items f where f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased');
  v_bp := v_l4 + v_prog >= v_l4max;
  v_room := greatest(0, least(v_batch, v_daymax - v_used));
  v_ai := security.ai_use_refusal_v1('enrich_fields');
  v_aim := security.ai_use_refusal_v1('entry_matrix');
  select o.remaining_usd into v_bal from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;
  v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
  v_why := case when v_owner is null then 'no owner to run as (Coverage › Attributes, Fill the gaps)'
                when v_ai is not null then 'AI reading is stopped (AI limits): ' || v_ai
                when v_room = 0 and v_daymax <= v_used then 'the daily cap is reached'
                when v_room = 0 then 'no course reads a run'
                when v_bal is not null and v_bal - v_room * v_cost < v_floor then 'the estimate would take the OpenRouter balance below its floor (Toolsets & limits)' end;

  if v_why is null then
    -- (b) held reads first, through D-R2: they replace the waiting item, so they also run under back-pressure
    for r in select * from security.aer_schedule_held_v1(least(v_heldmax, v_room)) loop
      v_checked := v_checked || jsonb_build_object('item_id', r.item_id, 'outcome', r.outcome);
      continue when not r.eligible;
      if p_preview then
        v_held := v_held || jsonb_build_object('item_id', r.item_id, 'course_id', r.course_id, 'provider_id', r.provider_id, 'country', r.country); v_nh := v_nh + 1;
        continue;
      end if;
      begin
        v_res := security.course_entry_correction_v1(r.item_id, v_owner,
                   'Scheduled entry reading (job aer-scheduled-read): the waiting read dropped printed requirements that no row covers; read again from the same stored page');
        v_held := v_held || jsonb_build_object('item_id', r.item_id, 'course_id', r.course_id, 'provider_id', r.provider_id, 'country', r.country, 'job_id', v_res->>'job_id');
        v_nh := v_nh + 1;
      exception when others then
        v_skip := v_skip || jsonb_build_object('item_id', r.item_id, 'why', left(sqlerrm, 300));
      end;
    end loop;
    -- (a) new course reads by eligibility rules, unless Layer 4 is full
    if not v_bp and v_room - v_nh > 0 then
      for r in select * from security.aer_schedule_courses_v1((v_room - v_nh) * 2) loop  -- fixed: twice the room, so courses the item gate holds can be passed over
        exit when v_nn >= v_room - v_nh;
        if security.enrich_item_held_v1(r.course_id, 'entry_requirements') then
          v_skip := v_skip || jsonb_build_object('course_id', r.course_id, 'why', 'held by the item gate'); continue;
        end if;
        if p_preview then
          v_new := v_new || jsonb_build_object('course_id', r.course_id, 'provider_id', r.provider_id, 'provider', r.provider_name, 'country', r.country); v_nn := v_nn + 1;
          continue;
        end if;
        begin
          v_job := security.course_entry_read_enqueue_v1(r.course_id, v_owner,
                     'Scheduled entry reading (job aer-scheduled-read): eligible course with no entry requirement held');
          v_new := v_new || jsonb_build_object('course_id', r.course_id, 'provider_id', r.provider_id, 'provider', r.provider_name, 'country', r.country, 'job_id', v_job);
          v_nn := v_nn + 1;
        exception when others then
          v_skip := v_skip || jsonb_build_object('course_id', r.course_id, 'why', left(sqlerrm, 300));
        end;
      end loop;
    end if;
  end if;

  -- (c) due entry pages fetched again (own lane and guard), unless Layer 4 is full
  if not v_bp and v_aim is null and v_mxmax > 0 then
    for r in select s.id, s.provider_id, s.read_via from pipeline.entry_matrix_sources s
              where s.status = 'read' and s.read_via <> 'stored'
                and s.read_at < now() - make_interval(days => security.pipeline_num_v1('entry.matrix_refresh_days', 30)::int)
                and security.entry_matrix_enabled_v1(s.provider_id)
              order by s.read_at, s.id limit v_mxmax loop
      if not p_preview then
        update pipeline.entry_matrix_sources f set status = 'found', attempts = 0, updated_at = now() where f.id = r.id and f.status = 'read';
      end if;
      v_mx := v_mx || jsonb_build_object('source_id', r.id, 'provider_id', r.provider_id, 'read_via', r.read_via);
      v_nm := v_nm + 1;
      if r.read_via = 'firecrawl' then v_fc := v_fc + 1; end if;
    end loop;
  end if;

  v_est := round((v_nh + v_nn) * v_cost, 4);
  if not p_preview then
    insert into pipeline.aer_schedule_checks(item_id, checked_at, outcome)
    select (c->>'item_id')::uuid, now(), c->>'outcome' from jsonb_array_elements(v_checked) c
    on conflict (item_id) do update set checked_at = excluded.checked_at, outcome = excluded.outcome;
    insert into pipeline.aer_schedule_runs(course_reads, corrections, matrix_pages, layer4_waiting, in_progress, back_pressure, used_before, room, refusal, estimate_usd, detail)
    values (v_nn, v_nh, v_nm, v_l4, v_prog, v_bp, v_used, v_room, v_why, v_est,
            jsonb_build_object('held', v_held, 'new', v_new, 'matrix', v_mx, 'skipped', v_skip, 'checked', jsonb_array_length(v_checked)));
  end if;
  return jsonb_build_object('preview', p_preview, 'course_reads', v_nn, 'corrections', v_nh, 'matrix_pages', v_nm, 'firecrawl_credits_estimate', v_fc,
    'estimate_usd', v_est, 'cost_per_course_usd', round(v_cost, 5), 'layer4_waiting', v_l4, 'in_progress', v_prog, 'layer4_max', v_l4max, 'back_pressure', v_bp,
    'used_24h', v_used, 'daily_max', v_daymax, 'room', v_room, 'refusal', v_why, 'matrix_refusal', case when v_aim is not null then 'AI reading is stopped (AI limits): ' || v_aim end,
    'balance_usd', v_bal, 'floor_usd', v_floor, 'checked', v_checked, 'held', v_held, 'new', v_new, 'matrix', v_mx, 'skipped', v_skip);
end $function$;
revoke all on function security.aer_schedule_tick_v1(boolean) from public, anon, authenticated;
comment on function security.aer_schedule_tick_v1(boolean) is 'CF-247 scheduled AER reading: job aer-scheduled-read. Held course reads read again through D-R2, new course reads by eligibility rules (security.course_entry_read_enqueue_v1), due entry pages fetched again; bounded by the run size and the daily cap, the AI lanes and the OpenRouter floor, and Layer 4 back-pressure. With true: what the run would ask, nothing written.';

-- the operator read for Course-level reading (rank 4 and above): next run, countries, daily figures, last runs. Read only.
create or replace function public.admin_aer_schedule(p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_rank int := coalesce(security.current_role_rank(), 0); v_next jsonb; v_rows int := security.pipeline_num_v1('aer.schedule_preview_rows', 30)::int;
        v_cost numeric := security.course_entry_cost_v1(); v_cap int := security.pipeline_num_v1('aer.schedule_daily_max', 200)::int;
begin
  if (auth.uid() is not null or coalesce(auth.role(), '') <> '') and (auth.uid() is null or v_rank < 4) then
    raise exception 'Pipeline Operator or above required' using errcode = '42501'; end if;
  v_next := security.aer_schedule_tick_v1(true);
  return jsonb_build_object(
    'job', (select jsonb_build_object('jobname', j.jobname, 'schedule', j.schedule, 'active', j.active) from cron.job j where j.jobname = 'aer-scheduled-read'),
    'next_run', v_next - 'checked' - 'new' - 'held' - 'matrix' - 'skipped'
                || jsonb_build_object('by_provider', (select coalesce(jsonb_agg(z order by z.n desc, z.provider), '[]'::jsonb) from (
                     select x->>'country' country, x->>'provider' provider, count(*) n from jsonb_array_elements(v_next->'new') x group by 1, 2 order by 3 desc, 2 limit v_rows) z),
                   'by_country', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select x->>'country' k, count(*) n from jsonb_array_elements(v_next->'new' || v_next->'held') x group by 1) z)),
    'countries', (with n as (select e.country, count(*) nc, count(distinct e.provider_id) np from security.aer_schedule_courses_v1(null, true) e group by 1)
                  select coalesce(jsonb_agg(security.aer_schedule_country_v1(cc) || jsonb_build_object('eligible_courses', coalesce(n.nc, 0),
                                                                                                      'eligible_providers', coalesce(n.np, 0)) order by cc), '[]'::jsonb)
                    from unnest(security.catalogue_country_codes_v1()) cc left join n on n.country = cc),
    'daily', jsonb_build_object('cap', v_cap, 'ai_usd_at_most', round(v_cap * v_cost, 2), 'cost_per_course_usd', round(v_cost, 5),
                                'course_reads_firecrawl', 0, 'used_24h', v_next->'used_24h'),
    'last_runs', (select coalesce(jsonb_agg(jsonb_build_object('ran_at', x.ran_at, 'course_reads', x.course_reads, 'corrections', x.corrections, 'matrix_pages', x.matrix_pages,
                                                               'back_pressure', x.back_pressure, 'refusal', x.refusal, 'estimate_usd', x.estimate_usd) order by x.ran_at desc), '[]'::jsonb)
                    from (select * from pipeline.aer_schedule_runs order by ran_at desc limit 5) x));  -- fixed: the last five runs are shown
end $function$;
revoke all on function public.admin_aer_schedule(jsonb) from public, anon;
grant execute on function public.admin_aer_schedule(jsonb) to authenticated;
comment on function public.admin_aer_schedule(jsonb) is 'CF-247 scheduled AER reading: Catalogue › Entry requirements › Course-level reading: the job state, what the next run of aer-scheduled-read would ask (by country and provider, held reads, entry pages, estimated US$ and Firecrawl credits), the countries (on, or off with the reason, and eligible courses), the daily figures and the last five runs. Rank 4 and above. Read only; never part of the consumer API.';

-- 4. edits to live functions (md5-guarded) ----------------------------------------------------------------------------------------------
-- while the job is on, eligibility rules replace the fixed entry.providers list
select pg_temp.edit_once('security.entry_matrix_enabled_v1(uuid)', '15fc1b28e855be2d4234057527a1a086', '582a5024ffeca0ac3c5446a903b39b3f', array[
 array[$o$     and (jsonb_array_length(coalesce(security.toolset_setting('pipeline', 'entry.providers'), '[]'::jsonb)) = 0
          or coalesce(security.toolset_setting('pipeline', 'entry.providers'), '[]'::jsonb) ? p_provider::text)$o$,
       $n$     -- CF-247 scheduled entry reading (3 Nov 2026): while job aer-scheduled-read is on, eligibility rules replace that list: an AER-eligible provider
     -- (security.aer_eligible_v1) of a country switched on for scheduled reading (security.aer_schedule_country_v1) with an entry page recorded
     and (case when security.aer_schedule_active_v1()
               then exists (select 1 from security.aer_eligible_v1() e where e.provider_id = p_provider and (security.aer_schedule_country_v1(e.country)->>'on')::boolean)
                    and exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = p_provider)
               else jsonb_array_length(coalesce(security.toolset_setting('pipeline', 'entry.providers'), '[]'::jsonb)) = 0
                    or coalesce(security.toolset_setting('pipeline', 'entry.providers'), '[]'::jsonb) ? p_provider::text end)$n$]
]::text[][], array[1]);

-- while the job is on, it owns the due entry-page refresh (bounded); paused, the refresh is as before
select pg_temp.edit_once('security.entry_matrix_fire_v1()', '869da9fbdbba2a8321d3f4f3dfba2197', '0ab725cb35f7c7d5d2309f18ec94c119', array[
 array[$o$     and security.entry_matrix_enabled_v1(f.provider_id);
  get diagnostics v_ref = row_count;$o$,
       $n$     and security.entry_matrix_enabled_v1(f.provider_id)
     and not security.aer_schedule_active_v1();  -- CF-247 (3 Nov 2026): while job aer-scheduled-read is on it refreshes due pages in bounded batches
  get diagnostics v_ref = row_count;$n$]
]::text[][], array[1]);

-- 5. Canada: off with its reason, and one integration-queue issue (not raised again by a second run) ------------------------------------
do $iq$
begin
  if not exists (select 1 from pipeline.integration_issues i where i.fingerprint = 'aer:country_not_configured:CA') then
    perform security.integration_issue_upsert_v1(jsonb_build_object(
      'fingerprint', 'aer:country_not_configured:CA',
      'title', 'Canada has no academic entry requirements (AER) configuration: scheduled entry reading is off for CA',
      'layer', 'AER', 'subsystem', 'pipeline.coverage_admission_countries (entry_requirements identities); aer.eligible_countries; job aer-scheduled-read',
      'country_codes', jsonb_build_array('CA'),
      'failure', 'No Canadian course page admits entry requirements (no identity basis is configured for entry_requirements in Canada), Canada is not in aer.eligible_countries, and no Canadian entry page is recorded. Scheduled entry reading therefore reads nothing in Canada and is switched off there with the reason "no AER configuration".',
      'expected', 'Canada has an approved AER configuration through the onboarding process (identity bases that admit entry requirements, AER eligibility, entry pages or a reader for Canadian provider requirements); then CA is taken off aer.schedule_countries_off and added to aer.schedule_countries, and the same schedule reads it.',
      'source', 'migration 20261103130000 (scheduled AER reading)', 'validation_layer', 'manual', 'root_cause_class', 'missing_dependency', 'severity', 'P2',
      'impact', (select count(*) || ' active Canadian courses have no academic entry requirement and none can be read' from catalogue.courses c join catalogue.providers p on p.id = c.provider_id
                  join ref.countries k on k.id = p.country_id where k.iso_alpha2 = 'CA' and c.lifecycle_status = 'active'),
      'workstream', 'A3',
      'evidence', jsonb_build_object('direction', 'Platform Admin 3 Nov 2026 09:32 §7: where a country-specific adapter does not exist, report it and route the work to the integration queue',
                                     'settings', jsonb_build_object('aer.schedule_countries_off', security.toolset_setting('pipeline', 'aer.schedule_countries_off'),
                                                                    'aer.eligible_countries', security.toolset_setting('pipeline', 'aer.eligible_countries')))),
      'migration 20261103130000');
  end if;
end $iq$;

-- 6. the job (G1): catalogued, created paused -------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('aer-scheduled-read', 'Course pages', 38, 'Entry requirements: scheduled reading',
  'Hourly at :13 when switched on: reads academic entry requirements without a person asking. Each run, within Scheduled entry reading: course reads asked a run and course reads a day at most, the Enrich fields AI lane and the OpenRouter floor: waiting course reads held as incomplete are read again from the same stored page (the corrected read replaces the waiting one only when complete); courses chosen by eligibility rules (AER-eligible provider of a country switched on, bound and stored official page, no requirement, nothing waiting, not recently read, not locked) get one stored-page read each; entry pages due again are fetched by Entry matrices: find and read. New reads stop while Layer 4 holds Scheduled entry reading: stop new reads while Layer 4 holds. Every read goes to Layer 4; nothing reaches the website until a person approves it. Preview of the next run on Catalogue › Entry requirements › Course-level reading. No Firecrawl for course reads.',
  6, false, null)
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'aer-scheduled-read') then
    perform cron.schedule('aer-scheduled-read', '13 * * * *', 'select security.aer_schedule_tick_v1()');
    perform cron.alter_job((select jobid from cron.job where jobname = 'aer-scheduled-read'), active := false);
  end if;
end $j$;

-- 7. register (housekeeping) ------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'aer-scheduled-read', 'Layer 2', 'Entry requirements', 'Scheduled AER reading by eligibility rules (paused until activated)', 'active', '{}', '20261103130000'),
 ('table', 'pipeline.aer_schedule_runs', 'Layer 2', 'Entry requirements', 'Runs of the scheduled AER reading (daily cap, back-pressure, what was asked)', 'active', '{}', '20261103130000'),
 ('table', 'pipeline.aer_schedule_checks', 'Layer 2', 'Entry requirements', 'Waiting course reads checked by the scheduled AER reading, in turn', 'active', '{}', '20261103130000'),
 ('function', 'security.aer_schedule_tick_v1', 'Layer 2', 'Entry requirements', 'Job aer-scheduled-read (and its preview)', 'active', '{}', '20261103130000'),
 ('function', 'security.aer_schedule_courses_v1', 'Layer 2', 'Entry requirements', 'Courses eligible for a scheduled entry read', 'active', '{}', '20261103130000'),
 ('function', 'security.aer_schedule_held_v1', 'Layer 2', 'Entry requirements', 'Held course reads correctable by a corrected read', 'active', '{}', '20261103130000'),
 ('function', 'security.aer_schedule_country_v1', 'Layer 2', 'Entry requirements', 'Per-country switch for scheduled entry reading', 'active', '{}', '20261103130000'),
 ('function', 'security.aer_schedule_active_v1', 'Layer 2', 'Entry requirements', 'Is the scheduled AER reading on', 'active', '{}', '20261103130000'),
 ('function', 'public.admin_aer_schedule', 'Layer 2', 'Entry requirements', 'Course-level reading: preview of the scheduled reading', 'active', '{}', '20261103130000')
on conflict do nothing;

-- 8. post-check ------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from cron.job where jobname = 'aer-scheduled-read' and active) then raise exception 'scheduled AER post-check: the job must be paused'; end if;
  if security.aer_schedule_active_v1() then raise exception 'scheduled AER post-check: nothing may switch on'; end if;
  if (security.aer_schedule_country_v1('CA')->>'on')::boolean or not (security.aer_schedule_country_v1('AU')->>'on')::boolean
     or not (security.aer_schedule_country_v1('NZ')->>'on')::boolean then raise exception 'scheduled AER post-check: AU and NZ on, CA off'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('aer.schedule_countries', 'aer.schedule_countries_off',
        'batch.aer_schedule_courses', 'aer.schedule_daily_max', 'batch.aer_schedule_held', 'aer.schedule_held_scan', 'aer.schedule_held_retry_days',
        'aer.schedule_held_max_tries', 'aer.schedule_layer4_max', 'aer.schedule_retry_days', 'aer.schedule_per_provider', 'aer.schedule_lock_fields',
        'batch.aer_schedule_matrix', 'aer.schedule_preview_rows') and label is not null and unit is not null and used_by is not null) <> 14 then
    raise exception 'scheduled AER post-check: settings incomplete (G2)'; end if;
  if not exists (select 1 from pipeline.integration_issues where fingerprint = 'aer:country_not_configured:CA') then
    raise exception 'scheduled AER post-check: the Canada issue is missing'; end if;
  if exists (select 1 from pipeline.aer_schedule_runs) or exists (select 1 from pipeline.aer_schedule_checks) then
    raise exception 'scheduled AER post-check: applying the migration must not run anything'; end if;
end $$;
select 'CF-247 scheduled AER reading: job aer-scheduled-read created paused; eligibility rules, held reads through D-R2, back-pressure, preview; CA off (integration issue)' ok;
