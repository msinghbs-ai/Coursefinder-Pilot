// CF-247 UI audit Phase 0 (Platform Admin 24 Oct 2026 11:27): errors shown to a person are plain, referenced and logged; a banner
// never follows a person to the next screen; a deployed-version change brings a reload notice; the incident fixes are in place.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { plainError, scrubInternals, rawFirstLine } from '../../src/lib/errors.js'
const shell = fs.readFileSync('src/mature-main.jsx', 'utf8')
const m = fs.readFileSync('supabase/migrations/20261024006000_cf247_ui_audit_phase0.sql', 'utf8')

test('plainError: known errors become sentences; raw Postgres wording, function signatures, vendor names and ids never reach the screen', () => {
  const raw = 'ERROR:  the link must be a full https:// web address\nCONTEXT:  PL/pgSQL function layer4_course_link_apply_impl(uuid,uuid,jsonb,text) line 10 at RAISE\nSQL statement "SELECT security.layer4_course_link_apply_impl(v_sys, v_item, …)"'
  expect(plainError(raw)).toBe('A course page address was not a secure (https) web address, so it was left for a person to check.')
  expect(plainError('canceling statement due to statement timeout')).toMatch(/took too long/)
  const odd = plainError('ERROR: security.some_step_v1(uuid) refused 3fa85f64-5717-4562-b3fc-2c963f66afa6 from firecrawl\nDETAIL: x')
  expect(odd).not.toMatch(/security\.|_v1\(|firecrawl|3fa85f64|ERROR|DETAIL/i)
  expect(odd.length).toBeLessThanOrEqual(161)
  expect(rawFirstLine('ERROR: a\nCONTEXT: b')).toBe('a')
  expect(scrubInternals('Something is broken')).toBe('Something is broken')
  expect(scrubInternals('job coverage-admit failed: ERROR: x CONTEXT: PL/pgSQL function f(uuid)')).not.toMatch(/CONTEXT|PL\/pgSQL/)
})

test('the shell: errors go through reportError with a reference, the banner clears on navigation, the deployed version is watched', () => {
  expect(shell).toContain("import{reportError,plainError}from'./lib/errors'")
  expect(shell).toContain("const report=m=>setError(m?reportError(m,route.page):'')")
  expect(shell).toContain("setNavOpen(false);setError('');")
  expect(shell).toContain('onError={report} navigate={go}/>')
  expect(shell).toContain('function DeployedVersionNotice(){')
  expect(shell).toContain("fetch(`/release-history.json?t=${Date.now()}`,{cache:'no-store'})")
  expect(shell).toContain('<DeployedVersionNotice/>')
  expect(shell).not.toContain('onError={setError} navigate={go}')
})

test('every panel errText is the shared plain reading', () => {
  const files = fs.readdirSync('src').filter(f => f.endsWith('.jsx'))
  for (const f of files) {
    const s = fs.readFileSync(`src/${f}`, 'utf8')
    const own = s.match(/^const errText=.*$/m)
    if (own) expect(own[0], f).toContain('plainError(e)')
  }
})

test('migration: error log table commented and RLS on; report function for signed-in users; coverage-admit http fix; readable fully-complete; no drops', () => {
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: /m); expect(m).not.toMatch(/^\s*(drop|truncate)\b/im)
  expect(m).toContain('create table if not exists pipeline.ui_error_log (')
  expect(m).toContain('comment on table pipeline.ui_error_log is')
  expect(m).toContain('alter table pipeline.ui_error_log enable row level security;')
  expect(m).toContain("if auth.uid() is null then raise exception 'sign in required' using errcode = '42501'; end if;")
  expect(m).toContain("select pg_temp.edit_n('security.coverage_admission_apply_v1(integer,text,text[])', '642639e240ccbca8444df2816209a86c', array[")
  expect(m).toContain("if v_rule like 'take:%' and coalesce(r.proposed->>'course_url', '') !~* '^https://' then v_rule := null; end if;")
  expect(m).toContain("select pg_temp.edit_n('security.course_completeness_build_v1()', '3de764fe1f20c99a96e3f867dd176dbd', array[")
  expect(m).toContain("count(*) filter (where state<>'no_reader')")
})
