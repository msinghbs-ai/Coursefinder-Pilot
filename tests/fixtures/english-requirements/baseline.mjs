#!/usr/bin/env node
// Guards: decision 19:14 §8 (Platform Admin 5 Nov 2026) for English requirements: the regression base of today's behaviour, taken from
// STORED evidence only (stored-outcomes.json, captured read-only from production; no page was fetched).
// Shared by tests/uat/cf-247-english-baseline-contract.spec.mjs (parser and recorded outcomes) and run.sh (database round trip).
//   node baseline.mjs record-inputs          prints the parsed results run.sh files through the live copy of svc_provider_policy_record
//   node baseline.mjs check-recorded <file>  checks the statuses the fixture database returned
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
import { execFileSync } from 'node:child_process'
import { fileURLToPath, pathToFileURL } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.resolve(HERE, '../../..')
export const STORED = JSON.parse(fs.readFileSync(path.join(HERE, 'stored-outcomes.json'), 'utf8'))

export const provider = (name) => STORED.providers.find((p) => p.provider === name)
export const source = (name, url) => provider(name).english_sources.find((s) => s.url === url)
export const UNSW_MAIN = 'https://www.unsw.edu.au/study/how-to-apply/english-language-requirements'

// The faculty rows of UNSW's English page, as far as stored evidence holds them verbatim: the quotes of the AI reading of 17 Oct 2026
// (proposal 46f58c9d, rejected by the Platform Admin at 15:01 as "one faculty row, not a university default"). Only these cells are stored
// as text in the database; the page itself is in the private evidence bucket (see README, "Verbatim pages"). The table layout around the
// cells (a heading, a header row with the two levels) is the layout the v0.2.x parser reported for the page (signal by_faculty: a level
// column header with faculty rows). It is a layout stand-in, not the page.
export function unswStoredCells() {
  const p = source('UNSW Sydney', UNSW_MAIN).proposals.find((x) => x.id === '46f58c9d-8407-44f7-b786-6156845fd906')
  const ug = p.proposal.defaults.undergraduate[0].quote, pg = p.proposal.defaults.postgraduate[0].quote
  const [faculty, ugCell] = ug.split(' | '), pgCell = pg.split(' | ')[1]
  return { faculty, ugCell, pgCell, md: `## IELTS Academic\n\n| Faculty | Undergraduate | Postgraduate coursework |\n|---|---|---|\n| ${faculty} | ${ugCell} | ${pgCell} |\n` }
}

export async function loadParser() {
  const out = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'h-policy-')), 'policy.mjs')
  execFileSync(path.join(ROOT, 'node_modules/.bin/esbuild'), [path.join(ROOT, 'supabase/functions/coverage-sweep/policy.ts'), '--format=esm', `--outfile=${out}`, '--log-level=error'])
  return import(pathToFileURL(out).href)
}

// What svc_provider_policy_record returns today for each stored case (run.sh files each one in the fixture database)
export async function recordInputs() {
  const { englishPolicy } = await loadParser()
  const main = source('UNSW Sydney', UNSW_MAIN)
  const ai = main.proposals.find((x) => x.id === '46f58c9d-8407-44f7-b786-6156845fd906')
  const auck = provider('University of Auckland').english_sources.map((s) => s.proposals.find((x) => x.parser.startsWith('ai:') && x.status === 'no_values')).filter(Boolean)
  return [
    { case: 'unsw-faculty-table-today-parser', expect: 'no_values', url: main.url, content_hash: main.content_hash, parsed: englishPolicy(unswStoredCells().md) },
    { case: 'unsw-stored-ai-reading-17-oct', expect: 'proposed', url: main.url, content_hash: main.content_hash, parsed: ai.proposal },
    ...auck.map((x, k) => ({ case: `auckland-stored-ai-reading-${k + 1}`, expect: 'no_values', url: x.id, content_hash: 'stored', parsed: x.proposal })),
  ]
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const cmd = process.argv[2]
  if (cmd === 'record-inputs') console.log(JSON.stringify(await recordInputs()))
  else if (cmd === 'check-recorded') {
    const want = Object.fromEntries((await recordInputs()).map((x) => [x.case, x.expect]))
    const got = Object.fromEntries(fs.readFileSync(process.argv[3], 'utf8').trim().split('\n').map((l) => l.split('|')))
    for (const [k, v] of Object.entries(want)) {
      if (got[k] !== v) { console.log(`FAIL ${k}: svc_provider_policy_record returned ${got[k]}, today's behaviour is ${v}`); process.exit(1) }
      console.log(`PASS today's behaviour: ${k} is filed as ${v}`)
    }
  } else { console.error('usage: baseline.mjs record-inputs | check-recorded <file>'); process.exit(2) }
}
