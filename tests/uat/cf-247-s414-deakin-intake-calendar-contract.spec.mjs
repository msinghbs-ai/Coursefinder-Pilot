// Guards: IQ-00313 P0 (Platform Admin directive 8 Nov 2026, Deakin commencement-date contamination): the year of a calendar start comes from the evidence (never the first year anywhere in the quote), a calendar date is taken only within the next cycle, a rejected or withdrawn value is not admitted again, the stored Website and Zoho items follow a withdrawal, the correction is count-guarded and audited, and the consumer API is untouched (G3); the cases run in CI on the production-equivalent fixture (tests/fixtures/deakin-intake-calendar)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261108050000_cf247_deakin_intake_calendar_year.sql'
const PASTE = 'docs/paste/PASTE-20261108-iq00313-deakin-intake-withdrawal.sql'
const FX = 'tests/fixtures/deakin-intake-calendar'
const sql = fs.readFileSync(MIG, 'utf8')
const body = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const paste = fs.readFileSync(PASTE, 'utf8')
const pasteBody = paste.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const read = (f) => fs.readFileSync(`${FX}/${f}`, 'utf8')

const INTAKES = ['97396154-52c5-4307-b9c3-bacadfcb2d23', '3cd3ac6f-3496-4eb1-8ad9-1e340d40b344', '222af1e5-ba50-4a8f-a8ad-ddddbc116839', '43e54175-53a6-4a59-b0cd-2745fd612895', 'e8c356bc-ca2a-4c62-98fc-f50c2bc2643f',
  '610b3e37-34ba-41bf-816f-fd502bd815de', 'fedaf904-a298-4e74-bc89-b9f55b241817', '26643e11-e587-4995-9d3e-3758b6d02859', 'b3104e40-36ad-4888-8b50-0dbf0de44add', 'bb847045-5dea-452b-b15c-d5ced763d8fe',
  '41956ca2-787b-4837-a6b4-f4bd4f681c77', '239b124f-2085-4c42-99d6-b4feef01de71']
const COURSES = ['2bc66924-be2c-4e68-9b21-101493cf8d95', '1f375f01-d4fd-46ea-8e2d-0834a8841682', '1c9362f8-9164-45fb-976e-684902f0c6b6', '10d34659-8bf9-4396-8745-49d4a21b7741', '0742996e-6f5c-4379-9b69-116d4176282c',
  '229ecc52-f1e7-4353-9e96-7b6359766545', '1c94e704-d9f6-47fb-8a69-f6fabfa11ef8', '240145f7-892d-473e-befe-e915d601f7a4', '1fd069e9-926b-49f1-97ab-11261d2040fd', '006fc6a4-ce91-4e2f-b251-16fa46df8c74',
  '34737033-8e05-4819-8878-df6de8033b94', '31a3c64e-7dba-43ec-a836-73006d6c471a']

test('the resolver dates a start from the evidence: the year after its date, else before it, else the end of a simple range less one when it wraps the year-end; never a year after several dates, never one the reader did not list', () => {
  expect(body).toContain('coalesce(y.y_after, y.y_head, y.y_range)')
  expect(body).toContain("'range ending ' || p.y_end || ': the start falls in ' || p.y_range")                 // the basis stays on the record (year_quote)
  expect(body).toContain('p.yrs @> to_jsonb(p.y_raw)')                                                            // the reader's own years must list it
  expect(body).toMatch(/then r\.rg\[5\]::int else r\.rg\[5\]::int - 1 end end y_range/)                           // a wrap of the year-end: the year before the printed one
  const fn = body.slice(body.indexOf('create or replace function security.calendar_proposal_dates_v1'), body.indexOf('comment on function security.calendar_proposal_dates_v1'))
  expect(fn).not.toMatch(/current_date|now\(\)|extract\(year from/)                                                  // never today's date or a rollover
  expect(body).toContain("md5(pg_get_functiondef('security.calendar_proposal_dates_v1(uuid)'::regprocedure)) <> '84aa52bcfa132b6308df5e402c82505f'")   // replaces exactly the production definition
  expect(body).toContain('returns table(proposal_id uuid, period text, kind text, year integer, month integer, day integer, on_date date, rolling_text text, quote text, applies_to text, meaning text, year_quote text)')   // signature unchanged
})

test('the plan takes a calendar date only within the next cycle (a setting), never a rejected calendar value, and never a withdrawn value again', () => {
  expect(body).toContain("'security.intake_dates_plan_v3(uuid[],integer)', '1d531a835fcaa6996ac32f88d218eea8'")
  expect(body).toContain("security.pipeline_num_v1('intake_dates.max_months_ahead', 18)")
  expect(body).toContain("(date_trunc('month', v_today) + make_interval(months => v_ahead))::date")
  expect(body).toContain('array[1, 1, 1, 1]')                                                                       // every edit applies exactly once
  expect(body).toContain('pipeline.intake_date_rejections j')
  expect(body).toContain("w.outcome = 'withdrawn'")
  expect(body).toContain("next_action := 'human_decision_required'; next_revisit_at := null;")
  // the course-specific offering gate and the unsupported-intake refusal are NOT edited here (they stay as released 5 Nov 2026)
  expect(body).not.toMatch(/intake_course_applicability_v1\(.*\) *(returns|language)/)
  expect(body).not.toContain('create or replace function security.intake_course_applicability_v1')
})

test('G2: the horizon is a setting with a label, range, unit and used_by line, and the code carries no operational number of its own', () => {
  expect(sql).toMatch(/'intake_dates\.max_months_ahead', 'Intake dates: [^']+',[\s\S]{0,800}'number', to_jsonb\(18\), 6, 36, 'months', 1012, 'Intake dates', 'security\.intake_dates_plan_v3; job intake-dates-apply'/)
  expect(body).toContain('on conflict (toolset_key, key) do nothing')
  expect(body).not.toMatch(/months => 18|interval '18 months'/)
})

test('new work is additive: a closed table with its comment, a reconciliation function, no drop or delete, and no consumer API object touched (G3)', () => {
  expect(body).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(sql).toMatch(/^-- Replaces: .+/m)
  expect(sql).toMatch(/^-- Retires: .+/m)
  expect(body).toContain('create table if not exists pipeline.intake_date_rejections')
  expect(body).toMatch(/comment on table pipeline\.intake_date_rejections is '/)
  expect(body).toContain('alter table pipeline.intake_date_rejections enable row level security')
  expect(body).toContain('revoke all on pipeline.intake_date_rejections from public, anon, authenticated')
  expect(body).not.toMatch(/\b(public\.website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|api\.)/)
  expect(body).not.toMatch(/create or replace function (api|public)\./)
  expect(body).not.toMatch(/cron\.(schedule|alter_job)/)                                                           // no new or changed scheduler
})

test('the stored Website and Zoho items follow a withdrawal with the scans\' own builders, transitions and locks, and only for the courses named', () => {
  const f = body.slice(body.indexOf('create or replace function security.intake_projection_reconcile_v1'), body.indexOf('revoke all on function security.intake_projection_reconcile_v1'))
  expect(f).toContain("pg_advisory_xact_lock(hashtext('website-sync-check'))")
  expect(f).toContain("pg_advisory_xact_lock(hashtext('zoho-sync-check'))")
  expect(f.indexOf('website_sync_item_v1')).toBeLessThan(f.indexOf('zoho_sync_item_v1'))                           // Zoho reads the stored Website item, so Website first
  expect(f).toContain('ref_id = any (p_course_ids)')
  expect(f).toContain("md5((v - 'generated_at' - 'freshness')::text)")                                            // the scans' own change test
  expect(f).toContain("nextval('pipeline.website_sync_seq')")
  expect(f).toContain("nextval('pipeline.zoho_sync_seq')")
  expect(f).not.toMatch(/insert into pipeline\.(website|zoho)_sync_items/)                                         // a new item is the scan's to create
  expect(body).toContain('revoke all on function security.intake_projection_reconcile_v1(uuid[]) from public, anon, authenticated')
  expect(f).toContain('security definer set search_path to')
})

test('the correction is a ready-to-run, count-guarded, audited file that uses the governed withdrawal only and writes no date', () => {
  for (const id of INTAKES) expect(paste, id).toContain(id)
  for (const id of COURSES) expect(paste, id).toContain(id)
  expect(paste.split('\n')[0]).toMatch(/^-- READY TO RUN, NOT RUN\./)
  expect(pasteBody).toContain('security.intake_date_withdraw_v1(r.intake_id, v_reason')
  expect(pasteBody).toMatch(/only % of % intakes match the contaminated value exactly; nothing changed/)       // 10 of 10
  expect(pasteBody).toMatch(/% active intakes hold the value, the list names %; stop and review/)             // nothing else holds it
  expect(pasteBody).toMatch(/only % of % intakes have the filled event of the named quote and reading/)       // written by the named job from the named quote
  expect(pasteBody).toContain('an intakes hold already exists on one of the courses: stop for its owner')      // never bypass a human lock
  expect(pasteBody).toContain("raise exception 'operation % already recorded: reconcile, do not replay'")
  expect(pasteBody).toContain("insert into pipeline.admin_control_events(area, action, target, detail, actor)")
  expect(pasteBody).toContain("'fields_changed', jsonb_build_array('intake_year', 'start_date')")
  expect(pasteBody).toContain("date '2028-11-01' as bad_date, 2028 as bad_year")
  expect(pasteBody).toContain("'Trimester 3: 1 Nov - 28 Jan 2028'")
  expect(pasteBody).toContain("to_regprocedure('security.intake_projection_reconcile_v1(uuid[])')")             // the stored items follow at once when the migration is released
  expect(pasteBody).toContain("to_regclass('pipeline.intake_date_rejections')")
  // it never writes a date or year, never touches the catalogue directly, and removes nothing
  expect(pasteBody).not.toMatch(/update\s+catalogue\./i)
  expect(pasteBody).not.toMatch(/\b(start_date|intake_year|application_deadline)\s*=\s*(date\s*)?'?\d{4}/)
  expect(pasteBody).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(pasteBody).not.toMatch(/delete\s+from|truncate\s+table|drop\s+(table|function)/i)
  expect(pasteBody).toContain('v_actor uuid := null;')                                                          // no invented user
  expect(pasteBody).toMatch(/^begin;/m); expect(pasteBody).toMatch(/^commit;/m)
})

test('the fixture reproduces the defect on the production code, then proves each rule, and mirrors the production NOT NULL sets', () => {
  const run = read('run.sh'), before = read('cases-before.sql'), after = read('cases-after.sql'), parity = read('parity-tables.sql'), cases = read('cases-paste.sql')
  expect(run).toContain('Refusing a remote database')
  expect(run).toContain("'security.calendar_proposal_dates_v1(uuid) 84aa52bcfa132b6308df5e402c82505f'")
  expect(run).toContain("'security.intake_dates_plan_v3(uuid[],integer) 1d531a835fcaa6996ac32f88d218eea8'")
  for (const m of ['cd15a2cb4c5cdb72c19c7792d9db430f', 'a4dce41ec4fd06e5262fdc7eb3e851d0', 'f8095625ca8c09526900c78c73a21a91', 'ea89266fb8d0bccb6226b463b92aac4e', '7ec06b8f3d039acc243a23c1db755864', 'd11a91ed6690ee705599e26d4e99b58a', '95d188d374b3edbf0b5cdcdc910c2e1a']) expect(run).toContain(m)   // the scans run verbatim
  expect(run).toContain('-1 -o /dev/null -f $MIG'); expect(run.match(/-1 -o \/dev\/null -f \$MIG/g).length).toBe(2)   // applied twice
  expect(run).toContain('FAIL consumer API changed by the migration (G3)')
  expect(run).toContain('FAIL the correction file ran twice')
  for (const k of ['PASS defect (resolver)', 'PASS defect (job)', 'PASS eligibility (before)', 'PASS defect (projections)']) expect(before).toContain(k)
  for (const k of ['PASS cross-year resolution', 'PASS eligibility', 'PASS horizon setting', 'PASS job', 'PASS rejection', 'PASS withdrawal', 'PASS no re-admission', 'PASS projections', 'PASS decisions']) expect(after).toContain(k)
  expect(cases).toContain('PASS correction')
  // NOT NULL sets of the written tables, as read from production on 8 Nov 2026 (the last release failed on a fixture that allowed a null production forbids)
  expect(parity).toContain("'course_id,id,intake_label,status'")
  expect(parity).toContain("'entity,entity_id,field,mode,set_at'")
  expect(parity).toContain("'action,area,created_at,detail,id'")
  expect(parity).toContain("'entity,item_key,seq,seq_at'")
  expect(parity).toContain('alter table pipeline.manual_locks alter column set_at set not null')
  expect(parity).toContain('alter table catalogue.course_intakes alter column course_id set not null, alter column intake_label set not null, alter column status set not null')
  // the cases cover the three eligibility refusals and the far period named in the directive
  for (const k of ["'Intakes Trimesters 1, 2'", "'Study with us. Apply now'", "'Student story: I commenced Trimester 3 2023 and loved it'", "'Intakes Trimester 6'"]) expect(before).toContain(k)
  expect(before).toContain("'Trimester 3: 1 Nov - 28 Jan ' || (y0 + 1)")                                           // the production quote
})

test('the fixture runs in CI beside the other intake fixtures', () => {
  const wf = fs.readFileSync('.github/workflows/intake-run-validate-test.yml', 'utf8')
  expect(wf).toContain("'tests/fixtures/deakin-intake-calendar/**'")
  expect(wf).toContain('bash tests/fixtures/deakin-intake-calendar/run.sh')
})
