// Guards: F-PDESC Directive 3 (Platform Admin, 9 Nov 2026) and G1: the provider-description job (352) fires every ten minutes (6 fires an hour) through a governed forward migration that changes only the schedule, refuses if the live schedule is neither the old nor the new value, and touches no function, setting, other job, table or the consumer API.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const MIG = fs.readFileSync('supabase/migrations/20261109183000_cf247_pdesc_cron_six_fires.sql', 'utf8')
const CODE = MIG.split('\n').filter((l) => !l.trimStart().startsWith('--')).join('\n')
const s216 = fs.readFileSync('tests/uat/cf-247-s216-p1-provider-descriptions-contract.spec.mjs', 'utf8')
const orig = fs.readFileSync('supabase/migrations/' + fs.readdirSync('supabase/migrations').find((f) => /provider_descriptions?/.test(f) && fs.readFileSync('supabase/migrations/' + f, 'utf8').includes("cron.schedule('provider-description-read'")), 'utf8')

test('housekeeping: Replaces and Retires lines (naming the catalogue and the help text), one alter_job on the one job, nothing dropped, no other object touched', () => {
  expect(MIG).toMatch(/^-- Replaces: .*6,16,26,56.*automation_catalogue.*pdesc\.every_minutes/m)
  expect(MIG).toMatch(/^-- Retires: nothing$/m)
  expect(CODE.match(/cron\.alter_job\(/g)).toHaveLength(1)
  expect(CODE).toContain("perform cron.alter_job(v_id, schedule := c_new);")
  expect(CODE).not.toMatch(/cron\.(schedule|unschedule)|command\s*:=|active\s*:=|\bdrop\b|\bdelete\b|\btruncate\b|\binsert\b|create |alter table|pipeline_num/i)
  // the only writes: the catalogue description and the help text (words, not values), each guarded and counted
  expect([...CODE.matchAll(/update ([a-z_.]+) set ([a-z_]+) =/g)].map((m) => m[1] + '.' + m[2])).toEqual(['pipeline.automation_catalogue.description', 'pipeline.platform_toolset_settings.help'])
  expect(CODE).toContain("where toolset_key = 'pipeline' and key = 'pdesc.every_minutes';")
  expect(CODE).not.toMatch(/set\s+(value|kind|unit|label|min|max|default)/i)
  expect(CODE).not.toMatch(/website_|zoho_|website-api|wix-|\bapi\./)
})

test('G1 record: the catalogue row and the setting help name the six fires; the :36 / :46 judgement and why the digit stays 6 are recorded', () => {
  expect(CODE).toContain("c_desc_new constant text := 'Every ten minutes, at :06, :16, :26, :36, :46 and :56 (six fires an hour;")
  expect(CODE).toContain("c_help_new constant text := 'The job wakes every ten minutes, at :06, :16, :26, :36, :46 and :56, and sends'")
  expect(CODE).toContain("neither the old nor the new wording; not overwritten")
  expect(MIG).toMatch(/Which minutes \(QA judgement/)
  expect(MIG).toMatch(/can only be ten minutes apart, so the choice is one minute digit/)
  expect(MIG).toContain('not guaranteed under load')
})

test('the new schedule is every ten minutes and the fire guard already allows that spacing (pdesc.every_minutes floor 10)', () => {
  expect(CODE).toContain("c_new constant text := '6,16,26,36,46,56 * * * *'; -- fixed:")
  expect(CODE).toContain("c_old constant text := '6,16,26,56 * * * *'; -- fixed:")
  const mins = '6,16,26,36,46,56'.split(',').map(Number)
  const gaps = mins.map((m, i) => (mins[(i + 1) % mins.length] - m + 60) % 60)
  expect(gaps).toEqual([10, 10, 10, 10, 10, 10])
  // the setting that spaces fires is the existing one; this change adds none
  const all = fs.readdirSync('supabase/migrations').map((f) => fs.readFileSync('supabase/migrations/' + f, 'utf8')).join('\n')
  expect(all).toMatch(/pdesc\.every_minutes/)
})

test('NEGATIVE: refuses when the job is missing or the live schedule is neither the old nor the new value; the new value is a no-op', () => {
  expect(CODE).toContain("if v_id is null then raise exception 'cron job provider-description-read does not exist'; end if;")
  expect(CODE).toContain("if v_sched = c_new then")
  expect(CODE).toContain("if md5(v_sched) <> '40439a43fa0f94e46d50c449afb9f46c' or v_sched <> c_old then")
  expect(CODE).toContain("not overwritten")
  // the guard hash is the md5 of the old schedule
  expect(crypto.createHash('md5').update('6,16,26,56 * * * *').digest('hex')).toBe('40439a43fa0f94e46d50c449afb9f46c')
})

test('the job is the catalogued one (G1) and the original migration still creates it at the old schedule; the active flag is not set here', () => {
  expect(s216).toContain("perform cron.schedule('provider-description-read', '6,16,26,56 * * * *', $j$select security.provider_description_fire_v1()$j$);")
  expect(orig).toContain("('provider-description-read', 'Course pages', 38, 'Provider descriptions: find, read and propose',")
  expect(CODE).toContain("where jobname = 'provider-description-read'")
})
