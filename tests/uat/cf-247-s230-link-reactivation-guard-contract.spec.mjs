// Guards: Platform Admin decision 3 Nov 2026 08:44 §5 (IQ-00043: replaced course links never reactivated)
// A course link that a person, a governed tranche or a rule set aside (inactive, deprecated, rejected, held) is never made active again by a
// background writer: 13 La Trobe links the 2 Nov tranche (event #28622) set inactive were re-activated every hour by exit-awards-apply through
// security.coverage_apply_course_v1 ("on conflict ... do update set status = 'active'"). The central guard is a trigger on catalogue.course_links
// (every writer, including live-only ones); the rediscovery is recorded as evidence; a person decides. The behaviour runs on isolated fixtures
// by tests/fixtures/link-reactivation/run.sh (scratch PostgreSQL; the live definitions loaded and checked against their live md5, the defect
// reproduced, the migration applied twice, eleven cases, and the paste file and rollback rehearsed on the measured 13).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261103080000_cf247_link_reactivation_guard.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/link-reactivation'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')
const PASTE = fs.readFileSync('docs/paste/PASTE-20261103-iq43-reactivated-links.sql', 'utf8')
const ROLLBACK = fs.readFileSync('docs/paste/PASTE-20261103-iq43-reactivated-links-rollback.sql', 'utf8')
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); return m.slice(a, m.indexOf('$$;', m.indexOf('as $$', a) + 5)) }

test('the two edited functions change only from their live md5 and are checked after; the fixtures load the live text and check it first', () => {
  expect(m).toContain("select pg_temp.edit_once('security.coverage_admission_apply_v1(integer,text,text[])', '7dea1ac5a96edc31ec4dd152d612aae1', '2e85e6cbb5d2e64ea1b50fe490c4da76'")
  expect(m).toContain("select pg_temp.edit_once('security.coverage_apply_course_v1(uuid,uuid,uuid,text,text,jsonb)', 'c2cbc9ab616a77487d447991f33daaeb', '66dbfd0739ce75f9ef0e20ca2d5975bd'")
  expect(m).toContain("if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;")
  for (const h of ['c2cbc9ab616a77487d447991f33daaeb', '7dea1ac5a96edc31ec4dd152d612aae1', '8bd718f741cad98b44accf5121aacecf', '7d12ababc9ca4ba3d4da7c6d0200dbdc', 'd0490f3707199988e87b5f37ca5e7342']) expect(run).toContain(h)
  expect(run).toContain('[ "$A1" = "2e85e6cbb5d2e64ea1b50fe490c4da76" ] && [ "$A2" = "66dbfd0739ce75f9ef0e20ca2d5975bd" ]')
  expect(run).toContain("grep -c 'already applied' | grep -qx 2")
  for (const f of ['security.coverage_apply_course_v1', 'security.coverage_admission_apply_v1', 'security.coverage_norm_url', 'security.course_held_v1', 'security.manual_fact_guard']) expect(fs.existsSync(`${FX}/live/${f}.sql`)).toBe(true)
  // the root cause, as live
  expect(fs.readFileSync(`${FX}/live/security.coverage_apply_course_v1.sql`, 'utf8')).toContain("on conflict (course_id, link_type, url) do update set status = 'active', source_id = excluded.source_id, evidence_id = excluded.evidence_id,")
  expect(before).toContain("raise notice 'defect superseded: the live coverage_apply_course_v1 sets the tranche''s inactive fragment link active again (two active links)';")
})

test('one rule names why an address must not come back: superseded, retired, a new spelling, held, rejected, replaced; an active link is never held', () => {
  const b = fn('security.course_link_hold_basis_v1')
  expect(b).toContain("if v_status = 'active' then return null; end if;")
  expect(b).toContain("if v_status in ('inactive', 'deprecated') then")
  expect(b).toContain("l.status in ('inactive', 'deprecated') and security.course_link_norm_v1(l.url) = v_norm")
  expect(b).toContain("exists (select 1 from pipeline.sources s where s.id = p_source and s.status = 'retired')")
  expect(b).toContain('if security.course_held_v1(p_course) then')
  expect(b).toContain("i.field_code = 'official_course_url' and i.status = 'pending'")
  expect(b).toContain('from pipeline.page_rejections r where r.course_id = p_course and security.course_link_norm_v1(r.url) = v_norm')
  expect(b).toContain('from pipeline.course_page_blocks b where b.course_id = p_course')
  expect(b).toContain("i.status = 'rejected'")
  expect(b).toContain("and jsonb_typeof(i.before_value) = 'array'")
  // the address comparison keeps the query (Auckland programme pages) and drops fragment, scheme, www, case and a trailing slash
  expect(m).toContain("'^https?://(www\\.)?', ''), '#.*$', ''), '/+(\\?|$)', '\\1'), '\\?$', '')")
})

test('the central guard: every writer of catalogue.course_links, after the lock guard, the row kept as it was, evidence recorded, a person decides', () => {
  const t = fn('security.course_link_reactivation_guard_trg_v1')
  expect(m).toContain('create trigger reactivation_guard before insert or update of status on catalogue.course_links')
  expect('reactivation_guard' > 'manual_lock_guard').toBe(true)   // BEFORE triggers fire by name: the lock guard first
  expect(t).toContain("if coalesce(current_setting('cf.manual_edit', true), '') = 'on' or auth.uid() is not null then return new; end if;")
  expect(t).toContain("if security.pipeline_num_v1('course_link.reactivation_guard', 1) < 1 then return new; end if;")
  expect(t).toContain("if TG_OP = 'UPDATE' then return old; end if;\n  return null;")
  expect(t).toContain('on conflict (course_id, link_type, url, route) do update')
  expect(t).toContain("using jsonb_build_object('fingerprint', 'course-link:reactivation-held',")
  expect(t).toContain('if v_new and to_regprocedure(')
  expect(t).not.toMatch(/raise exception/)
  expect(m).toContain('comment on table pipeline.course_link_rediscoveries is')
})

test('the Decision 263 rule never takes a held page, and the common write reports a held link', () => {
  expect(m).toContain("if v_rule like 'take:%' and security.course_link_hold_basis_v1(r.course_id, 'official_course', r.proposed->>'course_url', null) is not null then v_rule := null; end if;")
  expect(m).toContain("'link_held', nullif(btrim(p_payload->>'course_url'), '') is not null and v_links = 0);")
})

test('reconciliation: a read-only listing and a guarded paste file for exactly the measured 13, with rollback; nothing deleted', () => {
  const l = m.slice(m.indexOf('create or replace function security.course_link_reactivated_v1()'), m.indexOf("comment on function security.course_link_reactivated_v1()"))
  expect(l).toContain('language sql stable security definer')
  expect(l).not.toMatch(/\b(insert|update|delete)\b/i)
  expect(l).toContain("limit security.pipeline_num_v1('course_link.reactivated_list_max', 2000)::int")
  for (const p of [PASTE, ROLLBACK]) {
    expect(p).toContain("if v_n <> 13 or v_md5 <> 'e31aadeeb50cfc3da853d9a20908a3b6' then raise exception")
    expect(p).toContain("perform set_config('cf.manual_edit', 'on', true);")
    expect(p).toContain('if v_after is distinct from v_before then raise exception')
    expect(p).toContain('insert into pipeline.admin_control_events(area, action, target, detail)')
    expect(p).not.toMatch(/\b(delete|drop|truncate)\b/i)
  }
  expect(PASTE).toContain("raise exception 'IQ-00043 guard: the reactivation guard (migration 20261103080000) is not deployed; nothing changed';")
  expect(PASTE).toContain("and exists (select 1 from pipeline.admin_control_events e where e.id = 28622 and e.detail->'made_inactive' ? l.id::text)")
  expect(PASTE).toContain("'94137008f2b7784a78f806038d587ed1'")
  expect(m).not.toMatch(/^\s*(update|delete)\s+catalogue\./im)
})

test('fixture coverage: every route, a new link still admitted, a person, the switch, and the paste rehearsal', () => {
  for (const c of ['ok 1 superseded', 'ok 2 superseded spelling', 'ok 3 held', 'ok 3b an unverified link with no decision is re-admitted', 'ok 4 rejected by Layer 4',
    'ok 4b page rejection held', 'ok 5 locked', 'ok 6 retired', 'ok 7 a new course page is admitted', 'ok 8 a person', 'ok 9 rule', 'ok 10 switch 0', 'ok 11 restored set stays restored']) {
    expect(fixtures).toContain(`raise notice '${c}`)
  }
  expect(run).toContain('ok paste rehearsal: listing finds the 13; paste sets 13 inactive with an audit row, shown links unchanged; a second run is refused; rollback re-activates 13')
  expect(fs.readFileSync(`${FX}/paste-rehearsal-seed.sql`, 'utf8').match(/#\/overview\?studentType=int/g)).toHaveLength(13)
})
