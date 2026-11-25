// Guards: Platform Admin decision 26 Nov 2026 06:57 AEDT (option 2: proven sibling-page identity for academic entry requirements only, with its safeguards; no title-only, transitive or copied identity)
// s1191: security.entry_sibling_identity_v1 and the one-line change to security.aer_det_propose_v1; the course's own stored readings only; other fields' identity unchanged.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261129000000_cf247_s1191_entry_proven_sibling_page_identity.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1191: every safeguard of the decision is a condition of the proof', () => {
  expect(MIG).toContain('where o.provider_id = c.provider_id and o.id <> c.id and o.lifecycle_status = \'active\' and o.study_level_id = c.study_level_id')  // provider and level
  expect(MIG).toContain("lower(regexp_replace(regexp_replace(coalesce(o.canonical_title, ''), '\\(Level [0-9]+\\)', '', 'gi'), '[^[:alnum:]]', '', 'g')) = c.nt")  // normalised title
  expect(MIG).toContain("join pipeline.coverage_course_pages gp on gp.course_id = o.id and gp.url = p_url and gp.status = 'bound'")  // the same page
  expect(MIG).toContain("and gp.identity_basis in ('cricos_code', 'adapter_code')")  // proved by CRICOS or adapter, never by a sibling (not transitive)
  expect(MIG).toContain("if c.oi is not true then return jsonb_build_object('ok', false")  // international audience
  expect(MIG).toContain("if v_chk->>'verdict' = 'refuse' and coalesce(v_chk->>'rule', '') <> 'shared_page' then")  // the gate's page check, only the shared rule waived
  expect(MIG).toContain("\\mcampus\\M|\\monline\\M|on[- ]campus|part[- ]time|full[- ]time|\\mpathway|\\medition\\M|\\mintake\\M")  // no variant-specific requirement
})

test('s1191: one proposer line changes, md5 guarded; readings are the course own; other fields keep their rule; nothing dropped', () => {
  expect(MIG).toContain("if md5(pg_get_functiondef('security.aer_det_propose_v1()'::regprocedure)) <> '1eec1fef14b7a3eeef28dc33d5f02ef2' then")
  expect(MIG).toContain("if (length(d) - length(replace(d, v_old, ''))) / length(v_old) <> 1 then raise exception")
  expect(MIG).toContain("and (security.entry_sibling_identity_v1(pg.course_id, g.url)->>''ok'') is distinct from ''true'' then v_outcome := ''not_admitted'';")
  expect(MIG).toContain("raise exception 'post-check: the identity rule of other fields changed'")
  expect(code).not.toMatch(/insert into catalogue\.course_entry_requirements|update catalogue\.course_entry_requirements|coverage_admission_countries|cron\.schedule|cron\.alter_job|\bdelete from\b|truncate /i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l) || /^alter table .* drop /i.test(l))).toEqual([])
  for (const s of ['post-check: the proposer does not use the proven sibling page', 'post-check: the number of active cron jobs changed', 'post-check: manual locks changed', 'post-check: the consumer API moved']) expect(MIG).toContain(s)
})
