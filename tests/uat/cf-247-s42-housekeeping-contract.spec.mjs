// Guards: Housekeeping (Decision 260) with G1: Replaces/Retires lines, table purposes, every job catalogued, nothing dropped by a migration
// CF-247 v2.15.280 (S42): housekeeping standard (Decision 260). Platform Admin, 15 Oct 2026: "always keep the snapshot/documentation what
// corresponds to what and decommission as we create new approach. outcome is code/platform and database are always streamlined and secure".
// From 20261015030000 on, every migration says what it replaces and what it retires, every new table states its purpose, every new job is
// catalogued, and nothing is dropped by an applied migration.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { collect } from '../../scripts/component-register-collect.mjs'

const MIG_DIR = 'supabase/migrations'
const FIRST = '20261015030000'
const mig = fs.readFileSync(`${MIG_DIR}/${FIRST}_cf247_component_register.sql`, 'utf8')

export function housekeepingProblems(sql) {
  const out = []
  if (!/^-- Replaces: .+/m.test(sql)) out.push('no "-- Replaces:" line')
  if (!/^-- Retires: .+/m.test(sql)) out.push('no "-- Retires:" line')
  for (const m of sql.matchAll(/create table (?:if not exists )?([a-z_]+\.[a-z0-9_]+)/gi)) {
    if (!new RegExp(`comment on table ${m[1].replace('.', '\\.')} is '`, 'i').test(sql)) out.push(`table ${m[1]} has no purpose (comment on table)`)
  }
  for (const m of sql.matchAll(/cron\.schedule\(\s*'([^']+)'/g)) {
    const cat = sql.slice(sql.indexOf('insert into pipeline.automation_catalogue') + 1 || sql.length)
    if (!sql.includes('insert into pipeline.automation_catalogue') || !cat.includes(`('${m[1]}',`) || cat.indexOf(`('${m[1]}',`) > cat.indexOf('cron.schedule(')) out.push(`job ${m[1]} is not catalogued`)
  }
  const outsideFunctions = sql.replace(/\$function\$[\s\S]*?\$function\$/g, '')
  if (/^\s*(drop|delete|truncate)\b/im.test(outsideFunctions)) out.push('drops or deletes (use a paste file)')
  return out
}

test('every migration from Decision 260 on says what it replaces and retires, states table purposes, catalogues jobs, drops nothing', () => {
  const files = fs.readdirSync(MIG_DIR).filter((f) => f.endsWith('.sql') && f.slice(0, 14) >= FIRST).sort()
  expect(files[0]).toBe(`${FIRST}_cf247_component_register.sql`)
  for (const f of files) expect(housekeepingProblems(fs.readFileSync(`${MIG_DIR}/${f}`, 'utf8')), f).toEqual([])
  expect(housekeepingProblems("create table pipeline.x (a int);")).toContain('table pipeline.x has no purpose (comment on table)')
  expect(housekeepingProblems("-- Replaces: nothing\n-- Retires: nothing\nselect cron.schedule('y', '* * * * *', 'select 1');")).toEqual(['job y is not catalogued'])
})

test('the register: live jobs, tables and views; edge functions and screens from the repository; nothing removed, gone is retired', () => {
  expect(mig).toContain("kind text not null check (kind in ('job', 'table', 'view', 'edge_function', 'screen'))")
  expect(mig).toContain("status text not null default 'active' check (status in ('active', 'retiring', 'retired'))")
  expect(mig).toContain("update pipeline.component_register r set status = 'retired'")
  expect(mig).toContain("select cron.schedule('hygiene-check', '23 16 * * 0', 'select security.hygiene_check_v1()');")
  for (const k of ['unused_tables', 'unused_indexes', 'edge_functions_not_called', 'jobs_not_catalogued', 'tables_without_rls', 'definer_functions_without_search_path', 'public_functions_open_to_anon', 'ready_to_drop'])
    expect(mig).toContain(`'${k}'`)
  expect(mig).toContain("'pipeline:0:hygiene'")
  expect(fs.readFileSync('src/Toolsets.jsx', 'utf8')).toContain("case'pipeline:hygiene':")
})

test('the workflow collects edge functions, screens and calls, updates the register daily and commits the generated document to a snapshot branch', () => {
  const w = fs.readFileSync('.github/workflows/component-register.yml', 'utf8')
  expect(w).toContain('cron: "40 21 * * *"')
  expect(w).toContain('security.component_register_ingest_v1(')
  expect(w).toContain('git checkout -B component-register-snapshot')
  const p = collect({ result: [{ fn: 'coverage-sweep', n: 5, last: '2026-10-15T00:20:24.139000' }] })
  expect(p.edge_functions.map((e) => e.name)).toContain('coverage-sweep')
  expect(p.edge_functions.some((e) => e.name.startsWith('_'))).toBe(false)
  expect(p.screens.map((s) => s.name)).toContain('Dashboard')
  expect(p.edge_calls).toEqual([{ name: 'coverage-sweep', calls: 5, last: '2026-10-15T00:20:24Z' }])
})
