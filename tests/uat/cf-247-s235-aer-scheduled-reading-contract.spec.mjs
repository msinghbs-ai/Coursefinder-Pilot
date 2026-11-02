// Guards: Platform Admin direction 3 Nov 2026 09:32 (platform-led enrichment): academic entry requirements read on a schedule by eligibility rules
// Acceptance report item 4: AER had no scheduled work. Job aer-scheduled-read (created paused) asks, each run and within a run size, a daily
// cap, the existing AI lanes and the OpenRouter floor: held course reads read again through D-R2 (no second waiting item), new course reads
// by eligibility rules through the existing one-course stored-page enqueue, and due entry pages fetched again; new reads stop while Layer 4
// holds (back-pressure). Canada is off with its reason and an integration-queue issue. The database behaviour runs on isolated fixtures by
// tests/fixtures/aer-scheduled-reading/run.sh (scratch PostgreSQL: live definitions read 3 Nov 2026 10:14 AEDT, checked against their md5s;
// migration applied twice); this spec holds the contract. G2, G3 and housekeeping are guarded centrally (s32, s57, s42) and not re-asserted.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261103130000_cf247_aer_scheduled_reading.sql', 'utf8')
const FX = 'tests/fixtures/aer-scheduled-reading'
const fx = (f) => fs.readFileSync(`${FX}/${f}`, 'utf8')
const ui = fs.readFileSync('src/AerWorkspace.jsx', 'utf8')
const md5 = async (s) => (await import('node:crypto')).createHash('md5').update(s).digest('hex')

// [definition, live md5 before (3 Nov 2026 10:14 AEDT), md5 after]
const CHANGED = [
  ['security.entry_matrix_enabled_v1(uuid)', '15fc1b28e855be2d4234057527a1a086', '582a5024ffeca0ac3c5446a903b39b3f'],
  ['security.entry_matrix_fire_v1()', '869da9fbdbba2a8321d3f4f3dfba2197', '0ab725cb35f7c7d5d2309f18ec94c119'],
]

test('two md5-guarded edits from today\'s live text, and the definitions it calls are pinned; the fixtures load the live text and apply twice', async () => {
  const guarded = [...m.matchAll(/select pg_temp\.edit_once\('([^']+)', '([0-9a-f]{32})', '([0-9a-f]{32})'/g)].map(([, s, b, a]) => [s, b, a])
  expect(guarded.sort()).toEqual([...CHANGED].sort())
  for (const [sig, before] of CHANGED) expect(await md5(fx(`live/${sig.replace(/\(.*$/, '')}.sql`)), sig).toBe(before)
  for (const pin of ["('security.course_entry_read_enqueue_v1(uuid,uuid,text)', 'df0f2a2826e61b92b168847f1557435b')",
    "('security.course_entry_correction_v1(uuid,uuid,text)', '1e2947b30a02a38327e2b67e312339af')", "('security.course_entry_gate_v1(uuid,uuid[])', '4fc06c081e451f2d0fb0a504a4fbe10f')"]) expect(m).toContain(pin)
  const run = fx('run.sh')
  expect(run).toContain("grep -c ': applied' | grep -qx 2")
  expect(run).toContain("grep -c 'already applied' | grep -qx 2")
  expect(run).toContain('[ "$(snap)" = "$S1" ] || { echo "a second run changed rows')
  expect(fx('fixtures.sql').match(/raise notice 'PASS /g).length).toBe(8)
})

test('the job ships paused, catalogued, with no number in its command; paused, the matrix functions behave exactly as before', () => {
  expect(m).toContain("perform cron.schedule('aer-scheduled-read', '13 * * * *', 'select security.aer_schedule_tick_v1()');")
  expect(m).toContain("perform cron.alter_job((select jobid from cron.job where jobname = 'aer-scheduled-read'), active := false);")
  expect(m).toContain("raise exception 'scheduled AER post-check: the job must be paused'")
  expect(m).toContain("select exists (select 1 from cron.job j where j.jobname = 'aer-scheduled-read' and j.active)")
  // the fixed list stays the rule while paused; the fire's own refresh stays while paused
  expect(m).toMatch(/case when security\.aer_schedule_active_v1\(\)\n\s+then exists \(select 1 from security\.aer_eligible_v1\(\) e[\s\S]+?else jsonb_array_length\(coalesce\(security\.toolset_setting\('pipeline', 'entry\.providers'\)/)
  expect(m).toContain('and not security.aer_schedule_active_v1();  -- CF-247 (3 Nov 2026)')
  expect(m).not.toMatch(/update pipeline\.platform_toolset_settings/)
})

test('eligibility rules instead of fixed lists: AER-eligible provider, country switched on, bound stored page, nothing held, waiting, recent or locked', () => {
  expect(m).toContain('from security.aer_eligible_v1() e')
  expect(m).toContain("where (security.aer_schedule_country_v1(e.country)->>'on')::boolean")
  expect(m).toContain("join pipeline.evidence_artifacts a on a.id = g.evidence_id and a.storage_path is not null")
  expect(m).toContain("security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements')")
  expect(m).toContain("x.status in ('active', 'proposed')")
  expect(m).toContain("(f.state in ('queued', 'waiting', 'ai', 'leased', 'review') or f.updated_at > now() - s.retry)")
  expect(m).toContain("fl.reason_code = 'enrich_no_value' and fl.state in ('raised', 'counting')")
  // per-country switch: AU and NZ on; CA off with its reason, and one integration-queue issue
  expect(m).toMatch(/'aer\.schedule_countries'[\s\S]{0,600}?'list', '\["AU", "NZ"\]'::jsonb/)
  expect(m).toMatch(/'aer\.schedule_countries_off'[\s\S]{0,500}?'list', '\["CA=no AER configuration"\]'::jsonb/)
  expect(m).toContain("if not exists (select 1 from pipeline.integration_issues i where i.fingerprint = 'aer:country_not_configured:CA') then")
  expect(m).toMatch(/'severity', 'P2',[\s\S]{0,400}'workstream', 'A3'/)
})

test('reads go through the existing enqueue and D-R2; bounded by run size, daily cap, AI lanes and the floor; Layer 4 back-pressure', () => {
  expect(m).toContain('v_res := security.course_entry_correction_v1(r.item_id, v_owner,')
  expect(m).toContain('v_job := security.course_entry_read_enqueue_v1(r.course_id, v_owner,')
  expect(m).toContain("if security.enrich_item_held_v1(r.course_id, 'entry_requirements') then")
  expect(m).toContain("v_ai := security.ai_use_refusal_v1('enrich_fields');")
  expect(m).toContain("v_aim := security.ai_use_refusal_v1('entry_matrix');")
  expect(m).toContain("when v_bal is not null and v_bal - v_room * v_cost < v_floor then")
  expect(m).toContain('v_room := greatest(0, least(v_batch, v_daymax - v_used));')
  expect(m).toContain('v_bp := v_l4 + v_prog >= v_l4max;')
  expect(m).toContain('if not v_bp and v_room - v_nh > 0 then')
  expect(m).toContain('if not v_bp and v_aim is null and v_mxmax > 0 then')
  // held reads only where a corrected read can fix them; never a rows-cut or shared page read; tries and spacing are settings
  expect(m).toContain("elsif jsonb_array_length(coalesce(g->'drops_uncovered', '[]'::jsonb)) = 0 then outcome := 'held only for rows a person leaves out';")
  expect(m).toContain("security.pipeline_num_v1('aer.schedule_held_max_tries', 2)")
  // no extraction logic here: no AI or page call, no Layer 4 item written by the new code
  expect(m).not.toMatch(/svc_pilot_submit_nonce|insert into pipeline\.layer4_review_items|openrouter\.ai|firecrawl\.dev/)
})

test('Course-level reading previews the scheduled reading on request through a read-only rank-4 RPC', () => {
  expect(m).toContain("v_next := security.aer_schedule_tick_v1(true);")
  expect(m).toContain("raise exception 'Pipeline Operator or above required' using errcode = '42501'; end if;")
  expect(ui).toContain("supabase.rpc('admin_aer_schedule',{p_args:{}})")
  expect(ui).toContain('data-aer-schedule-preview>Preview scheduled reading</Button>')
  expect(ui).toContain('c=>` · ${c.country} off: ${c.reason}`')
})
