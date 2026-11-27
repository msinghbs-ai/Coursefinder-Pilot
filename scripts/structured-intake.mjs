// CF-247 s1321 (S1-Build; SS-Programme-Control 27 Nov 2026 21:08 AEDT, approved exception 1): structured intake operations. A submitter's
// candidate file is read from the admin repository at a named commit (docs/intake/<submitter>/<batch>.jsonl, one candidate a line, or a JSON
// list) and submitted through the governed writer public.svc_structured_intake_v1; the platform proves every quote on its own stored copies and
// decides through the existing writers and admission rules. No SQL other than that call is sent, and nothing is fetched from a university here.
import { need, op, lit, summary } from './boost-live-lib.mjs'
import crypto from 'node:crypto'
import fs from 'node:fs'

need()
const [action, file, ref, by] = process.argv.slice(2)
if (!['submit', 'verify', 'list'].includes(action)) { console.error('::error::action is submit, verify or list'); process.exit(1) }
if (!by || !String(by).trim()) { console.error('::error::who is acting (by) is required'); process.exit(1) }
const call = async (a, args) => (await op(`select public.svc_structured_intake_v1(${lit(a)}, ${lit(JSON.stringify(args))}::jsonb, ${lit(by)}) as r`))?.[0]?.r
const m = /^docs\/intake\/([a-z0-9][a-z0-9_-]{1,40})\/([A-Za-z0-9._-]{1,120})\.(jsonl|json)$/.exec(String(file || ''))
if (!m) { console.error('::error::file is docs/intake/<submitter>/<batch>.jsonl in the admin repository'); process.exit(1) }
const [, submitter, batch] = m
const out = { action, file, ref, submitter, batch }
if (action === 'submit') {
  if (!/^[0-9a-f]{40}$/.test(String(ref || ''))) { console.error('::error::ref is the admin repository commit (40 hex characters)'); process.exit(1) }
  const res = await fetch(`https://raw.githubusercontent.com/msinghbs-ai/coursefinder-admin/${ref}/${file}`)
  if (!res.ok) { console.error(`::error::the file could not be read at that commit (HTTP ${res.status})`); process.exit(1) }
  const text = await res.text()
  out.sha256 = crypto.createHash('sha256').update(text).digest('hex')
  const items = file.endsWith('.json') ? JSON.parse(text) : text.split('\n').filter((l) => l.trim()).map((l) => JSON.parse(l))
  out.submitted = items.length
  out.submit = await call('submit', { submitter, batch, items })
} else if (action === 'verify') out.verify = await call('verify', {})
// wait for the worker's proofs (at most four minutes), then list
for (let k = 0; k < 24; k++) {  // fixed: wait bound of the run (24 looks, 10 s apart)
  out.list = await call('list', { submitter, batch })
  if (!(out.list?.items || []).some((x) => ['received', 'verifying'].includes(x.status))) break
  await new Promise((r) => setTimeout(r, 10000))
}
fs.mkdirSync('out', { recursive: true })
fs.writeFileSync('out/structured-intake.json', JSON.stringify(out, null, 2))
const rows = (out.list?.items || []).map((x) => `| ${x.domain} | ${x.course_code || ''} | ${x.status} | ${String(x.reason || '').slice(0, 160).replace(/\|/g, '/')} | ${x.review_item_id || ''} | ${(x.rows || []).map((r) => r.status).join(', ')} |`)
await summary([`Structured intake ${action}: ${submitter} / ${batch}${out.sha256 ? ` (file sha256 ${out.sha256.slice(0, 12)}…)` : ''}`, '',
  out.submit ? `Received ${out.submit.received}, duplicates ${out.submit.duplicates}, refused ${(out.submit.refused || []).length}` : '', '',
  '| Domain | Course | Status | Reason | Layer 4 item | Rows |', '|---|---|---|---|---|---|', ...rows].join('\n'))
console.log(JSON.stringify(out.submit || out.verify || {}, null, 2))
