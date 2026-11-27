#!/usr/bin/env node
// CF-247 s1298 (S1-Build; design coursefinder-admin #1271 Phase B): read-only audience and identity signals of stored course pages, by provider and URL template.
// It lists the named providers' active courses that are open (or not known closed) to international students and have a stored course-page copy, groups them by
// template (host and path family of the bound page), takes a few courses per template, and asks the coverage-sweep worker's read-only mode audience_inspect for
// their signals (no model call, no web fetch, no write). Writes out/audience-inspect.json and a summary. Argument 1: provider names (comma-separated, matched from
// the start of the canonical name); argument 2: courses per template (default 3, at most 6); argument 3: courses in all (default 60, at most 160).
import fs from 'node:fs'
import { need, read, lit, worker, summary } from './boost-live-lib.mjs'
need()
const names = String(process.argv[2] || '').split(',').map((s) => s.trim()).filter(Boolean)
if (!names.length || names.length > 12) throw Error('provider names: 1 to 12')
const per = Math.min(Math.max(Number(process.argv[3] || 3), 1), 6), max = Math.min(Math.max(Number(process.argv[4] || 60), 1), 160)  // fixed: diagnostic bounds
const pat = names.map((n) => n.replace(/[^a-z0-9 ]/gi, '').toLowerCase()).join('|')
const rows = await read(`with c as (
  select c.id, c.course_code, p.canonical_name provider, g.url,
         lower(substring(g.url from '^https?://([^/?#]+)')) || regexp_replace(lower(coalesce(substring(g.url from '^https?://[^/?#]+(/[^?#]*)'), '/')), '/[^/]+/?$', '/*') template
    from catalogue.courses c join catalogue.providers p on p.id = c.provider_id
    join pipeline.coverage_course_pages g on g.course_id = c.id join pipeline.evidence_artifacts e on e.id = g.evidence_id
   where p.publication_status = 'published' and c.lifecycle_status = 'active' and c.open_to_international is not false and e.storage_path is not null
     and lower(p.canonical_name) ~ ${lit('^(' + pat + ')')})
select * from (select c.*, row_number() over (partition by provider, template order by md5(id::text)) k, count(*) over (partition by provider, template) n_template from c) z
 where k <= ${per} order by provider, n_template desc, template limit ${max}`)
const pages = []
for (let k = 0; k < rows.length; k += 10) {  // a small batch keeps one worker answer well under the response size pg_net keeps
  const chunk = rows.slice(k, k + 10)
  const res = await worker(`jsonb_build_object('mode', 'audience_inspect', 'course_ids', to_jsonb(array[${chunk.map((x) => lit(x.id)).join(', ')}]::text[]))`)
  if (res.mode !== 'audience_inspect') throw Error('the worker did not answer in mode audience_inspect')
  for (const p of res.pages || []) { const r = chunk.find((x) => x.id === p.course_id) || {}; pages.push({ ...p, provider: r.provider, template: r.template, n_template: Number(r.n_template || 0), course_code: r.course_code }) }
}
fs.mkdirSync('out', { recursive: true })
fs.writeFileSync('out/audience-inspect.json', JSON.stringify({ names, per, at: new Date().toISOString(), courses: rows.length, pages }, null, 1))
const groups = new Map()
for (const p of pages) { const key = `${p.provider} | ${p.template}`; if (!groups.has(key)) groups.set(key, []); groups.get(key).push(p) }
let md = `### Audience inspect (read only, stored copies)\n\n${pages.length} pages; no model call, no fetch, no write.\n\n| Provider | Template (courses) | Views | Code on page | Toggle | Params | International links |\n|---|---|---|---|---|---|---|\n`
for (const [key, ps] of groups) {
  const [prov, tpl] = key.split(' | '), v = {}; for (const p of ps) v[p.error ? 'error' : p.view] = (v[p.error ? 'error' : p.view] || 0) + 1
  md += `| ${prov} | ${tpl} (${ps[0].n_template}) | ${Object.entries(v).map(([a, b]) => a + ' ' + b).join(', ')} | ${ps.filter((p) => p.code_on_page).length}/${ps.length} | ${ps.filter((p) => p.toggle && p.toggle.international && p.toggle.domestic).length} | ${[...new Set(ps.flatMap((p) => p.params || []))].slice(0, 4).join(' ')} | ${[...new Set(ps.flatMap((p) => p.intl_links || []))].slice(0, 2).join(' ').slice(0, 160)} |\n`
}
await summary(md)
