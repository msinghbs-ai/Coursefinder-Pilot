// Guards: Layer 4 integrator handover (Platform Admin 3 Nov 2026) Priority 3 items 9-12, evidence recovery mandate 20:47 §6 and overnight mandate 21:59 (D4, D5, D6, IQ-00132): approved single scholarship reads, owner checks before spend, no directory-site queuing, sources and ownership root causes
// One held scholarship can be read on its own (VU 1323, Bond 1230), freshly where asked, on the normal scholarship path, logged and within an
// allowance that ships at 0; its answer goes to the held item in Layer 4 and is never applied. Held items on directory pages get an owner
// proposal with evidence; nothing is reassigned. The database behaviour runs on isolated fixtures by tests/fixtures/sch-reads-ownership/run.sh
// (scratch PostgreSQL; the live definitions checked against the md5s read on 3 Nov 2026); this spec holds the contract and the fixtures' case
// lines. G2, G3 and housekeeping are guarded centrally (s32, s57, s42) and not re-asserted here.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104250000_cf247_sch_reads_ownership.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/sch-reads-ownership'
const fx = (f) => fs.readFileSync(`${FX}/${f}`, 'utf8')
const paste = (f) => fs.readFileSync(`docs/paste/${f}`, 'utf8')
const fn = (name) => m.slice(m.indexOf(`create or replace function ${name}(`), m.indexOf('$function$;', m.indexOf(`create or replace function ${name}(`)))

test('four md5-guarded edits from live text; lands after workstream A; v2.15.434 functions untouched', () => {
  const guarded = [...m.matchAll(/select pg_temp\.edit_once\('([^']+)',\s*'([0-9a-f]{32})', '([0-9a-f]{32})'/g)].map(([, s, b, a]) => [s, b, a])
  expect(guarded).toEqual([
    ['public.svc_scholarship_ai_next(integer)', '18e76dbc9984be55370434ca27066c7b', '709ad0f93b16e99f8962e85671f0b291'],
    ['security.scholarship_ai_has_copy_v1(bigint)', '08db702a7e4231ea00acf36da80c04d4', 'ecc54cd39a4fb9fc9c4c2217f6548d30'],
    ['public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)', 'aa337a9fb30a75452a7b54bddbf8d00f', 'b2fafccb2532afc3e0d1337588b5c43d'],
    ['security.scholarship_ai_enqueue_v1(text,uuid[],uuid,boolean)', '04a9aa8c56fc0d5593c813da3ecd270d', '549948c5251a1ce3d424266d155e70cb']])
  expect(m).toContain("to_regclass('pipeline.ops_remedies') is null")
  expect(m).toContain("'0f10b0a35109fd6a6c6be36e4d4ea26d'") // review_open_v1 read, not edited
  for (const f of ['scholarship_coverage_v1', 'scholarship_discovery_settle', 'scholarship_discovery_hold_reason_v1', 'aer_provider_states_v1', 'coverage_reconcile_v1'])
    expect(m, f).not.toMatch(new RegExp(`create or replace function security\\.${f}|edit_once\\('security\\.${f}`))
  const run = fx('run.sh')
  expect(run).toContain('["$SAI"]=18e76dbc9984be55370434ca27066c7b')
  expect(run).toContain('["$REC"]=aa337a9fb30a75452a7b54bddbf8d00f')
  expect(run).toContain('["$ENQ"]=04a9aa8c56fc0d5593c813da3ecd270d')
  expect(run).toContain("grep -c ': already applied$')\" = 4")
})

test('the single read: one held item, logged, refused without approval, owner checks before credits, allowance ships at 0', () => {
  expect(m).toMatch(/'scholarship\.single_read_daily_max'[\s\S]{0,600}?'number', to_jsonb\(0\), 0, 10, 'reads'/)
  const req = fn('security.scholarship_read_request_v1')
  expect(req).toContain("raise exception 'a single read is requested by a Platform Admin paste (postgres) only'")
  for (const why of ["'directory site: the page is not the provider''s own; decide the owner first'", "'the owner is in question: decide the owner proposal first'",
                     "'a read of this item is already queued'", "'single reads are off or today''s allowance is used"]) expect(req, why).toContain(why)
  expect(req.match(/insert into pipeline\.scholarship_ai_queue/g)).toHaveLength(1)
  expect(req).toContain('fresh_read, read_request_id)')
  expect(m).toMatch(/create unique index if not exists scholarship_read_requests_open on pipeline\.scholarship_read_requests\(review_id\) where state = 'queued'/)
  const c = fx('fixtures.sql')
  for (const l of ["'R1 refused while off: '", "'R2 the third read of the day is refused: '", "'R2 exactly two queue rows'", "'R10 a directory page is refused before any credit'",
                   "'R10 an open owner proposal blocks the read'"]) expect(c).toContain(l)
})

test('a fresh read is given no stored copy; a request-bound answer goes to Layer 4 and is never applied; a dead page costs one read', () => {
  expect(m).toContain("'storage_path', case when u.fresh_read then null else coalesce(u.storage_path,")
  expect(m).toContain('where q.id = p_queue_id and not q.fresh_read')
  expect(m).toMatch(/if q\.read_request_id is not null then\s+if p_error is null or q\.attempts >= 3 then\s+r := security\.scholarship_read_request_close_v1/)
  expect(m).toContain('if q.read_request_id is not null and p_error is not null and p_storage_path is null then')
  expect(fn('security.scholarship_read_request_close_v1')).toContain('security.scholarship_ai_review_open_v1(p_extraction, p_reason)')
  expect(fn('security.scholarship_read_request_close_v1')).not.toMatch(/scholarship_ai_apply_v1|review_apply_v1|admit_from_provider_page/)
  expect(fx('fixtures-before.sql')).toContain('B1 reproduced: the Bond read is given the old stored copy')
  const c = fx('fixtures.sql')
  for (const l of ["'R4 queue ' || (e->>'queue_id') || ' is read from the page (no stored copy given)'", "'R5 step 2 is given the fresh copy, not the 29 Sep copy'",
                   "'R5 nothing applied, admitted or decided'", "'R5 request read; the round quote is recorded for the person'", "'R6 no retry and no other model'",
                   "'R8 an ordinary settled answer is applied as before'"]) expect(c).toContain(l)
})

test('owner proposals record evidence only; the decision and the approved reads are count-guarded paste files', () => {
  const own = fn('security.scholarship_owner_check_v1')
  expect(own).not.toMatch(/update pipeline\.scholarship_ai_reviews|update pipeline\.scholarship_page_candidates|review_apply_v1|update scholarship\.scholarships/)
  expect(own).toContain('security.coverage_country(pt.id) is not distinct from security.coverage_country(rv.provider_id)')
  expect(m).toMatch(/ops_remedy_register_v1\('sch_owner_proposals', jsonb_build_object\('authority', 'auto'/)
  for (const r of ['sch_owner_decision', 'sch_single_approved_read', 'sch_duplicate_close', 'sch_staging_reread']) expect(m).toMatch(new RegExp(`ops_remedy_register_v1\\('${r}', jsonb_build_object\\('authority', 'admin'`))
  expect(m).toMatch(/ops_remedy_register_v1\('course_link_cricos_identity', jsonb_build_object\('authority', 'release'/)
  const p1 = paste('PASTE-20261104-sch-approved-reads-vu1323-bond1230.sql')
  expect(p1).toContain("security.scholarship_read_request_v1(1323, false,")
  expect(p1).toContain("security.scholarship_read_request_v1(1230, true,")
  expect(p1).toContain("if v_n <> 2 then raise exception 'guard: % queue rows bound to the 2 requests")
  expect(p1.match(/set value = to_jsonb\(0\)/g)).toHaveLength(1)
  const p2 = paste('PASTE-20261104-sch-owner-refuse-from-holder.sql')
  expect(p2).toContain("'. Platform Admin decision D4, overnight mandate 3 Nov 2026 21:59; submitted by the Integration Controller.'")
  expect(p2).not.toContain('<date and time>')
  expect(p2).not.toMatch(/insert into scholarship\.scholarships|update scholarship\.scholarships|provider_id\s*=\s*'[0-9a-f-]{36}'\s*where/)
  expect(p2).toContain("if v_n <> 21 then raise exception 'guard: % of 21 refused; rolled back'")
  const p3 = paste('PASTE-20261104-sch-macquarie-staging-reread.sql')
  expect(p3).toContain("v_since timestamptz := '2026-11-03 21:59:00+11'")
  for (const k of ["'already asked for'", "'read since the decision'", "'stored since the decision'", "'queued for an AI read'"]) expect(p3, k).toContain(k)
  expect(p3).toContain("if v_n <> 8 - v_skip then raise exception")
  expect(p3).not.toMatch(/publication_status\s*=|lifecycle_status\s*=\s*'inactive'/)
  const c = fx('fixtures.sql')
  for (const l of ["'R9 1177 names Alphacrucis College (AU), not the NZ record'", "'R9 a generic word (International) never names an owner'", "'R9 the held items are untouched'",
                   "'R11 report: Macquarie 1184 duplicates active a347e086'"]) expect(c).toContain(l)
})

test('IQ-00132: the enqueue never queues a directory-site candidate or re-read; it marks the candidate refused once (not needed); ships on, can be switched off', () => {
  expect(m).toMatch(/'scholarship\.enqueue_directory_gate_on'[\s\S]{0,700}?'number', to_jsonb\(1\), 0, 1/)
  expect(m).toContain("v_gate boolean := security.pipeline_num_v1('scholarship.enqueue_directory_gate_on', 1) >= 1;")
  expect(m).toContain("set admit_status = 'skipped', admit_reasons = array['directory_site']")
  expect(m).toContain("and not exists (select 1 from pipeline.scholarship_ai_reviews r where r.candidate_id = c.id and r.status = 'pending')")
  expect(m).toContain("'outcome', 'not_needed', 'issue', 'IQ-00132'")
  expect(m).toContain('and not (v_gate and security.third_party_host_v1(coalesce(c.final_url, c.url)))')
  expect(m).toContain('and not (v_gate and security.third_party_host_v1(coalesce(sp.final_url, sp.url)))')
  expect(fx('fixtures-before.sql')).toContain('B3 reproduced:')
  const c = fx('fixtures.sql')
  for (const l of ["'E1 no directory-site row is queued (candidates or re-reads)'", "'E1 the provider''s own pages are still queued'", "'E2 logged as not needed'",
                   "'E3 a candidate with a pending held item (1174) is left to Layer 4, not marked'", "'E3 a second enqueue marks nothing again and queues nothing on directory sites'",
                   "'E4 with the gate off the enqueue behaves as before'"]) expect(c).toContain(l)
})
