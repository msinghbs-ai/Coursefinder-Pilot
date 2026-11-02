// Intake dates fixtures: the stored calendar document (calendar.md, years relative to today so the fixtures never age) read by the real
// parser (coverage-sweep policy.ts calendarStarts, calendar-dates-v1), printed as the proposal JSON a person approves. Used by run.sh.
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
const out = path.join(os.tmpdir(), `intake-policy-${process.pid}.mjs`)
execFileSync('node_modules/.bin/esbuild', ['supabase/functions/coverage-sweep/policy.ts', '--format=esm', `--outfile=${out}`, '--log-level=error'])
const { calendarStarts } = await import(out)
fs.rmSync(out, { force: true })
const Y = new Date().getFullYear()
const md = fs.readFileSync(new URL('./calendar.md', import.meta.url), 'utf8').replaceAll('{N}', String(Y + 1)).replaceAll('{Y}', String(Y))
process.stdout.write(JSON.stringify(calendarStarts(md)))
