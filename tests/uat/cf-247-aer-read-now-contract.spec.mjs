// Guards: Platform Admin decision 10 Nov 2026 19:47 (one primary outcome action for academic entry requirements; F-AER.01-.06), F-AER.04 (first reads and protected changes stay human Layer 4 decisions; nothing here approves, admits, activates or publishes), G2 (no operational value in code), G3 (consumer API untouched) and the standing hard limits (no scraper, no page search, no E13 AI re-read, no setting changed): migration 20261110220000 composes the existing readers, checks every reviewer packet for country, qualification, grade, scale, applicability, source page and year without filling any, adds the Data Delivery reviewer key and stops one deliberately-off switch turning a whole stream off.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261110220000_cf247_aer_read_now.sql', 'utf8')
const held = fs.readFileSync('supabase/held/aer_read_now_forward_recovery.sql', 'utf8')
const wf = fs.readFileSync('.github/workflows/aer-read-now-test.yml', 'utf8')
const sql = mig.replace(/--[^\n]*/g, '') // code only: the header comments describe what is NOT done
const comp = fs.readFileSync('src/AerReadNow.jsx', 'utf8')
const ws = fs.readFileSync('src/AerWorkspace.jsx', 'utf8')
const er = fs.readFileSync('src/EntryRequirements.jsx', 'utf8')

test('the action composes the existing readers only: no scraper, no page search, no E13 AI re-read, no approval, no setting, no new job', () => {
  for (const fn of ['course_entry_read_enqueue_v1', 'aer_reread_v1', 'aer_replay_plan_v1', 'aer_replay_apply_v1', 'aer_parked_items_v1', 'aer_review_kinds_v1', 'ai_use_refusal_v1', 'course_entry_cost_v1', 'aer_schedule_country_v1', 'coverage_identity_allowed', 'entry_matrix_enabled_v1']) expect(sql).toContain(`security.${fn}`)
  expect(sql).not.toMatch(/aer_e13_recover_v1|firecrawl|fc_setting|web_search|fetch_url|http_get|net\.http|aer_source_stored_find_v1\s*\(|entry_matrix_fire_v1\s*\(/i)
  // it writes only its own event row, and the existing functions it calls write the reads
  const writes = [...sql.matchAll(/\b(insert into|update|delete from)\s+([a-z_.]+)/gi)].map(m => `${m[1].toLowerCase()} ${m[2]}`)
  expect([...new Set(writes)].sort()).toEqual(['insert into pipeline.admin_control_events', 'insert into pipeline.component_register'])
  expect(sql).not.toMatch(/update\s+catalogue\.|insert\s+into\s+catalogue\.|publication_status\s*=\s*'published'/i)
  expect(sql).not.toMatch(/cron\.(schedule|alter_job|unschedule)|automation_catalogue|admin_job_kinds/)
  expect(sql).not.toMatch(/platform_toolset_settings\s*\(|update\s+pipeline\.platform_toolset_settings/)
})

test('human approval is preserved: the plan returns a person for a ready packet, the wrapper cannot approve, and every started read waits in Layer 4', () => {
  expect(sql).toContain("'human_review_required', 'packet_ready'")
  expect(sql).toContain('Nothing is published until a person decides')
  expect(sql).toContain('Every result waits in Layer 4 for a person')
  expect(sql).not.toMatch(/layer4_decide|layer4_approve|machine_admit|admit_v1/i)
  expect(sql).toContain('v_rank < 6') // fixed: Platform Admin, the rank of the existing per-course read and per-source read again
  expect(sql).toContain("'permission_denied'")
})

test('the plan separates the nine outcomes and shares the scheduled reader\'s allowances', () => {
  for (const o of ['queued', 'in_progress', 'human_review_required', 'already_up_to_date', 'no_eligible_work', 'source_unavailable', 'switch_off', 'budget_reached', 'permission_denied']) expect(sql).toContain(`'${o}'`)
  for (const k of ['aer.schedule_daily_max', 'aer.schedule_per_provider', 'aer.schedule_layer4_max', 'aer.replay_on', 'aer.replay_daily_max', 'aer.replay_per_provider', 'aer.e13_recover_on', 'aer.source_stored_find_on', 'entry.course_read_countries', 'credit_floor_usd']) expect(sql).toContain(`'${k}'`)
  expect(sql).toContain('pg_advisory_xact_lock') // a duplicate click waits, then finds the first one's work in flight
  expect(sql).toContain("e.area = 'aer_read_now'") // on-demand reads are counted against the same daily allowance
})

test('a missing fact is flagged, never filled or inferred', () => {
  expect(sql).toContain("'not_stated'")
  expect(sql).toContain("'not_recorded'")
  expect(sql).toContain('never filled in, inferred from another row or country')
  for (const f of ['country', 'qualification', 'grade', 'scale', 'applicability', 'source_page', 'year']) expect(sql).toContain(`'${f}'`)
  // the capture date is not a printed year
  expect(mig).toMatch(/as_at is the date the page was read, never a year the page states/)
  expect(sql).not.toMatch(/coalesce\(\s*[a-z]\.(intake_year|grade_scale|country_code|min_grade)/)
})

test('the header records the live md5s and the edits are guarded, idempotent and taken back by a held file; G2/G3 are untouched', () => {
  expect(mig).toMatch(/^-- Replaces: /m); expect(mig).toMatch(/^-- Retires: nothing/m)
  for (const h of ['d593eb0aa0fe06b0b4b28c86821bfff5', '27a42c5f02d09f518e77bd965814bbe0', '330e079018c93f8db8a649ed3a08ae12', '208067f054c2f3ac7adb1196e3e8c25c']) { expect(mig).toContain(h); expect(held).toContain(h) }
  expect(mig).toContain('differs from the definition this change edits')
  expect(mig).toContain('already applied')
  expect(held).toMatch(/Repeatable\./)
  expect(sql).not.toMatch(/\bdrop\s+(function|table|view|schema|column)|\bdelete\s+from|\btruncate\b/i)
  // G3: nothing the website or Zoho reads
  expect(sql).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\.[a-z_]+\(|zoho_|wix-course-api|website-course-api/)
  // G2: every constant is marked, and the daily window is the scheduled reader's own
  for (const m of sql.split('\n').filter(l => /interval '1 day'/.test(l))) expect(mig).toContain('-- fixed:')
  expect(wf).toContain('tests/fixtures/aer-read-now/run.sh')
  for (const p of ['supabase/migrations/20261110220000_cf247_aer_read_now.sql', 'supabase/held/aer_read_now_forward_recovery.sql', 'tests/fixtures/aer-read-now/**']) expect(wf).toContain(p)
})

test('Data Delivery (server keys only; the screen is left to the Data Delivery work): the aer stream gains the reviewer key, and a lane\'s recovery is off only when every one of its switches is off', () => {
  expect(mig).toContain("'reviewer', rvw.j")
  expect(mig).toContain('cardinality(v_sw) > 0 and cardinality(v_sw) = v_sw_all')
  expect(mig).toContain("'switches_off', to_jsonb(v_sw)")
  // this change does not touch the Data Delivery screen or the catalogue filters (coordinator scope, 10 Nov 2026)
  expect(fs.readFileSync('src/DataDelivery.jsx', 'utf8')).not.toContain('AerReviewer')
})

test('the screens: one component in the AER workspace (three views), Provider detail and Course detail; one RPC; the earlier direct read is kept as an advanced control', () => {
  expect(comp).toContain("supabase.rpc('admin_aer_read_now',{p_args:args})")
  expect(comp).not.toMatch(/supabase\.from\(|admin_aer'|admin_entry_requirements|admin_enrich_fields|admin_jobs/)
  expect(comp).toContain('label="Read / refresh entry requirements now"')
  expect(comp.split('\n').filter(l => !l.startsWith('//')).join('\n')).not.toMatch(/\bpublished\b/i) // a packet awaiting a person is never called published (comment lines excluded)
  expect(comp).toContain("'Not measured'")
  expect((ws.match(/<AerReadNow /g) || []).length).toBe(3)
  expect(ws).toContain("import AerReadNow from'./AerReadNow'")
  expect(er).toContain('<AerReadNow providerId={providerId}/>')
  expect(er).toContain('<AerReadNow courseId={courseId} onError={onError} onChanged={load}/>')
  expect(er).toContain('data-course-entry-read-advanced')
  expect(er).toContain('<ReasonAction label="Read from the stored page"')
  // the poll is a screen refresh and says so; no other number
  expect(comp).toContain('const POLL_MS=15000 // fixed:')
  // the files owned elsewhere are not touched
  for (const f of ['src/ProviderFillFields.jsx']) expect(comp + ws + er).not.toContain(f)
})

test('Operating Model v1.7 scope: absence is named from existing state, with no new table, state or enum, and the Data Delivery screen and catalogue filters are untouched', () => {
  const code = mig.split('\n').filter(l => !l.trim().startsWith('--')).join('\n')
  expect(code).not.toMatch(/create\s+table|create\s+type|alter\s+table|create\s+index/i)
  for (const fn of ['aer_read_now_class_v1', 'aer_read_now_source_v1']) expect(mig).toContain(`security.${fn}`)
  // the six kinds, derived from the outcome and reason that already exist
  for (const k of ['no_source_on_record', 'source_found_not_read', 'tried_not_found', 'technical_failure', 'budget_hold', 'human_review']) { expect(mig).toContain(`'${k}'`); expect(comp).toContain(k) }
  // "tried, not found" is said only from a stored result; the over-row-limit hold is shown as recorded and is not turned into a search finding
  expect(mig).toContain("r.reason in ('the page does not state it', 'no quoted requirement was on the page', 'no row met the admission rules')")
  // unchanged evidence: the same stored copy or the same content hash
  expect(mig).toContain('e2.content_hash = e1.content_hash')
  // the nine outcomes are unchanged (the six kinds are labels, not outcomes)
  expect(comp).toContain("permission_denied:['danger','Permission denied']")
  for (const f of ['src/DataDelivery.jsx', 'src/CatalogueColumns.jsx', 'src/data-delivery.css']) { const t = fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : ''; expect(t).not.toContain('aer_read_now'); expect(t).not.toContain('AerReadNow') }
})

test('QA round: no unfiltered parked/readiness join per request, reader holds are not absences, a failed read is not re-queued against an unchanged page, the cap counts every on-demand read', () => {
  const code = mig.split('\n').filter(l => !l.trim().startsWith('--')).join('\n')
  // B1: the parked lookup is per item (the unique work_items key); the unfiltered function is not called by any new function (it is only named in the guard list)
  expect(code).not.toMatch(/(from|join)\s+security\.aer_parked_items_v1\(\)/i)
  expect(code).toContain("w.entity = i.id::text")
  expect(code).toContain('v_hold_ids') // the held ids are passed down, not fetched again
  expect(code).toContain('v_ready_ids') // the ready ids are passed to the facts check, not fetched again
  // B2: a held read is a hold for a person; tried, not found only for a finished run with no row kept
  expect(code).toContain("'reader_held'")
  expect(code).toContain("lr.error like 'held%'")
  expect(code).not.toMatch(/held_unparsed%'\)\s*\)?\s*n_none|n_none[^;]*held_unparsed/)
  expect(code).toContain("lr.state = 'done' and coalesce(lr.rows_admitted, 0) = 0")
  // (a) once asked for this content hash, a failed read is not queued again before the retry interval; the cap counts rereads and replays
  expect(code).toContain("'technical_failure_retried'")
  expect(code).toContain('make_interval(days => v_retry)')
  expect(code).toContain("(e.detail->>'rereads')::int")
  expect(code).toContain("(e.detail->>'replays')::int")
  // (b) honest label: nothing on record is not a finding that discovery ran
  expect(comp).toContain("no_source_on_record:'No source on record'")
  expect(comp).not.toContain('No official source found')
  // (d) the anchored Data Delivery edit is asserted against the recorded after md5 when applied to the recorded body
  expect(code).toContain('(r.must_match or v_at_before) and md5(v_src) <> r.md5_after')
  // (e) the displayed state change is global and said so
  expect(mig).toContain('THE DISPLAYED STATE CHANGES FOR MORE THAN AER')
})
