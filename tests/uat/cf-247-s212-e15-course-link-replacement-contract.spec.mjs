// Guards: E15 course-link replacement (Platform Admin overnight mandate 1 Nov 2026 22:01; record §36.1)
// CF-247 S207. A Layer 4 course-link decision ("Use the new page" = approve, "Enter another address" = edit_and_approve) makes the chosen page
// THE course page: the course's other active official links become inactive (kept, not deleted), the chosen link is active and primary,
// catalogue.courses.course_url follows, a page set by hand on the course record is refused with a plain message (the manual-lock guard used to
// skip the insert silently, so WI0194 and MITO 4226 read "approved" with nothing changed), and a skipped row is never recorded as applied.
// The edit is checked against the live definition captured on 1 Nov 2026 (md5 e97b56cc...): applying the migration's edits reproduces the
// after md5 that the rolled-back dry run reported.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const FILE = 'supabase/migrations/20261101120000_cf247_e15_course_link_replacement.sql'
const m = fs.readFileSync(FILE, 'utf8')
const before = fs.readFileSync('tests/uat/fixtures/cf-247-s212/layer4_course_link_apply_impl.before.sql', 'utf8')
const BEFORE = 'e97b56cc87d02c4886df39918027eecc'
const AFTER = '75a53dbbcd5e20e1018a05b61f6763aa'
const md5 = (s) => crypto.createHash('md5').update(s, 'utf8').digest('hex')
const code = (s) => s.replace(/--[^\n]*/g, '')
const edits = [...m.matchAll(/array\[\$o\$([\s\S]*?)\$o\$,\s*\$n\$([\s\S]*?)\$n\$\]/g)].map((x) => [x[1], x[2]])
const after = edits.reduce((d, [o, n]) => d.split(o).join(n), before)

test('migration: one md5-guarded edit of the course-link apply, header complete', () => {
  expect(m).toContain(`select pg_temp.edit_once('security.layer4_course_link_apply_impl(uuid,uuid,jsonb,text)', '${BEFORE}', '${AFTER}', array[`)
  expect(m).toContain(`-- Before: ${BEFORE}. After: ${AFTER}`)
  expect(m).toMatch(/^-- Why: /m)
  expect(m).toMatch(/^-- What /m)
  expect(m).toMatch(/^-- Rollback: /m)
  expect(m).toMatch(/^-- Replaces: security\.layer4_course_link_apply_impl/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  expect(m).toContain('array[1,1,1,1]);')
  expect(m.match(/select pg_temp\.edit_once\(/g)).toHaveLength(1)
})

test('the edits apply exactly once each to the live definition and give the dry-run md5', () => {
  expect(md5(before)).toBe(BEFORE)
  expect(edits).toHaveLength(4)
  for (const [o] of edits) expect(before.split(o).length - 1, o.slice(0, 80)).toBe(1)
  expect(md5(after)).toBe(AFTER)
})

test('the approved page retires the course\'s other official pages, becomes primary, and the course record follows', () => {
  const lock = after.indexOf("l.field in ('official_url','course_url')")
  const retire = after.indexOf("update catalogue.course_links set status='inactive',is_primary=false,updated_at=now()\n   where course_id=v_item.entity_id and link_type='official_course' and status='active' and url<>v_url;")
  const insert = after.indexOf('insert into catalogue.course_links(')
  expect(lock).toBeGreaterThan(0)
  expect(retire).toBeGreaterThan(lock)
  expect(insert).toBeGreaterThan(retire)
  expect(after).toContain("'Official provider course page (confirmed by reviewer)',true,'active',")
  expect(after).toContain("do update set label=excluded.label,status='active',is_primary=true,")
  expect(after).toContain("if v_link is null then raise exception 'the course page was not saved")
  expect(after).toContain('update catalogue.courses set course_url=v_url,updated_at=now() where id=v_item.entity_id and course_url is distinct from v_url;')
  expect(after).toContain("'superseded_links',v_retired")
  // the status written is one the check constraint allows (active, inactive, deprecated, unverified)
  expect([...after.matchAll(/status='([a-z]+)'/g)].map((x) => x[1]).every((s) => ['active', 'inactive', 'deprecated', 'unverified'].includes(s))).toBe(true)
  // the existing validation stays in front of every write
  expect(after.indexOf("security.reference_url_has_use(v_url, 'not_course_page')")).toBeLessThan(lock)
})

test('a page set by hand is refused with a plain message, not skipped', () => {
  expect(after).toContain("if exists (select 1 from pipeline.manual_locks l where l.entity='course' and l.entity_id=v_item.entity_id and l.field in ('official_url','course_url')) then")
  expect(after).toContain("raise exception 'this course''s page was set by hand on the course record: change it there (course detail, official page), or keep the page we hold';")
  expect(after).not.toMatch(/set_config\('cf\.manual_edit'/)
  expect(after).not.toMatch(/manual_locks[^;]*\b(insert|update|delete)\b|\b(insert into|update|delete from)\s+pipeline\.manual_locks/i)
})

test('nothing dropped or deleted, no consumer API object touched, no operational value written in', () => {
  expect(code(m)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  for (const [, n] of edits) expect(n).not.toMatch(/\b(drop|delete|truncate)\b/i)
  expect(code(m)).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|function\s+api\.|\bapi\.[a-z_]+\(/)
  expect(m).not.toMatch(/Consumer API change approved/)
  for (const [, n] of edits) {
    expect(n).not.toMatch(/interval\s+'\d+/i)
    expect(n).not.toMatch(/\blimit\s+\d/i)
  }
})
