#!/usr/bin/env node
// Guards: decision 19:14 §8 (Platform Admin 5 Nov 2026): validation uses production-representative constraints, grants, RLS, triggers and
// function signatures. Lesson: the intake releases passed simplified fixtures that lacked admin_jobs_outcome_fkey and the manual_locks
// mode/primary key, and production rejected the operation.
//
// Production-parity capture tool (agent E). It never connects to production itself:
//   1 capture-sql  prints ONE read-only SELECT (tests/fixtures/prod-parity/capture.sql filled with the scope). Run it through
//                  mcp__Supabase__execute_sql on fxcwkweaxjtknorudmwp (light catalogue read; never at minutes :35-:42 or :47-:48 Sydney)
//                  or psql against a local database, and save the result.
//   2 save         turns the saved tool output (the MCP text, a JSON array of rows, or the bare manifest) into a manifest file, after checking
//                  every function definition against its captured md5 (a transcription error is refused).
//   3 fixture      prints fixture SQL for an isolated local PostgreSQL that reproduces the captured columns and types, defaults, keys,
//                  foreign keys (referenced tables with their key columns only; named lookup tables seeded with their code rows), check
//                  constraints, indexes, triggers, RLS and policies, table and function grants, role time-outs and function definitions.
//   4 check-sql    prints ONE read-only SELECT that recomputes the facts on any database and lists every difference from the manifest
//                  (no rows = parity). Run it on the local fixture database, and on production to prove the manifest is still current.
//   5 diff         compares the facts of two manifests (e.g. production against a manifest captured from a fixture database).
// Lookup rows are code values only: a lookup table with a column that looks like personal data, or more rows than --max-lookup-rows, is refused.
import fs from 'node:fs'
import crypto from 'node:crypto'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const TEMPLATE = path.join(ROOT, 'tests/fixtures/prod-parity/capture.sql')
const IDENT = /^[a-z_][a-z0-9_$]*\.[a-z_][a-z0-9_$]*$/
const SIG = /^[a-z_][a-z0-9_$]*\.[a-z_][a-z0-9_$]*(\([a-z0-9_ ,.\[\]"]*\))?$/i
// Columns that suggest personal or user data: a lookup table carrying one is refused rather than copied.
export const PERSONAL = '(email|phone|mobile|password|secret|token|address|birth|first_name|last_name|full_name|given_name|family_name|user_id|_by$|^actor|ip_addr|^ip$|passport|contact)'
const KNOWN_ROLES = ['anon', 'authenticated', 'service_role', 'authenticator']
const CMD = { r: 'select', a: 'insert', w: 'update', d: 'delete', '*': 'all' }

const lit = (s) => (s == null ? 'null' : "'" + String(s).replaceAll("'", "''") + "'")
function dollar(s, tag = 'pp') { let t = tag; while (String(s).includes(`$${t}$`)) t += 'x'; return `$${t}$${s}$${t}$` }
const md5 = (s) => crypto.createHash('md5').update(s, 'utf8').digest('hex')
const qid = (fq) => fq.split('.').map((p) => (/^[a-z_][a-z0-9_]*$/.test(p) ? p : '"' + p.replaceAll('"', '""') + '"')).join('.')
const role = (r) => (r === 'PUBLIC' || r === 'public' ? 'public' : /^[a-z_][a-z0-9_]*$/.test(r) ? r : '"' + r.replaceAll('"', '""') + '"')

export function normaliseScope({ tables = [], functions = [], lookups = [], maxLookupRows = 500 } = {}) {
  const clean = (xs) => [...new Set(xs.map((x) => x.trim()).filter(Boolean))].sort()
  const s = { tables: clean(tables), functions: clean(functions), lookups: clean(lookups), max_lookup_rows: Number(maxLookupRows) }
  for (const t of [...s.tables, ...s.lookups]) if (!IDENT.test(t)) throw Error(`not a schema.table name: ${t}`)
  for (const f of s.functions) if (!SIG.test(f)) throw Error(`not a schema.function or schema.function(args) name: ${f}`)
  for (const t of s.lookups) if (/^(auth|storage|vault|realtime)\./.test(t)) throw Error(`refused: ${t} is not a code table`)
  if (!(s.max_lookup_rows > 0 && s.max_lookup_rows <= 5000)) throw Error('--max-lookup-rows must be 1..5000')
  return s
}

export function captureSql(scopeIn) {
  const s = normaliseScope({ ...scopeIn, maxLookupRows: scopeIn.max_lookup_rows ?? scopeIn.maxLookupRows })
  const n = s.max_lookup_rows
  const lookups = s.lookups.map((t) => `
  union all select z.fq, z.refused, case when z.refused is null then (select jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text) from ${qid(t)} r) end
    from (select ${lit(t)}::text fq, case when exists (select 1 from pg_attribute, personal where attrelid = ${lit(t)}::regclass and attnum > 0 and not attisdropped and attname ~* personal.p)
            then 'refused: a column looks like personal data' when (select count(*) from (select 1 from ${qid(t)} limit ${n + 1}) y) > ${n} then 'refused: more than ${n} rows' end refused) z`).join('')
  const scope = JSON.stringify({ tables: s.tables, functions: s.functions, lookups: s.lookups, max_lookup_rows: n })
  const body = fs.readFileSync(TEMPLATE, 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n').trim()
  return body.replace('{{SCOPE}}', () => dollar(scope, 'scope')).replace('{{PERSONAL}}', () => lit(PERSONAL)).replace('{{LOOKUP_ROWS}}', () => lookups) + '\n'
}

// The tool output can be MCP text (with the untrusted-data wrapper), a JSON array of rows, a row, or the manifest itself.
export function parseCaptured(text) {
  let v
  try { v = JSON.parse(text) } catch { v = null }
  if (v && typeof v.result === 'string') return parseCaptured(v.result)
  if (v == null) {
    const m = text.match(/\[\s*\{[\s\S]*\}\s*\]/)
    if (!m) throw Error('no JSON rows found in the captured output')
    v = JSON.parse(m[0])
  }
  if (Array.isArray(v)) v = v[0]
  if (v && v.manifest) v = typeof v.manifest === 'string' ? JSON.parse(v.manifest) : v.manifest
  if (!v || v.tool !== 'prod-parity-capture v1' || !v.facts) throw Error('not a prod-parity manifest')
  return v
}

export function verifyManifest(m) {
  const problems = []
  for (const f of m.functions) {
    if (md5(f.def) !== f.md5) problems.push(`function ${f.sig}: definition md5 ${md5(f.def)} differs from captured ${f.md5}`)
    if (m.facts[`function|${f.sig}`] !== `${f.md5}|${f.kind}`) problems.push(`function ${f.sig}: fact differs from its entry`)
  }
  for (const t of m.tables) if (m.facts[`table|${t.fq}`]?.split('|')[0] !== t.kind) problems.push(`table ${t.fq}: fact missing`)
  for (const t of m.tables.filter((x) => x.kind === 'lookup')) if (t.rows) {
    const bad = t.rows.flatMap((r) => Object.keys(r)).filter((k) => new RegExp(PERSONAL, 'i').test(k))
    if (bad.length) problems.push(`lookup ${t.fq}: personal-data column ${bad[0]}`)
  }
  return problems
}

function rolesUsed(m) {
  const rs = new Set(KNOWN_ROLES)
  for (const g of m.schemas || []) rs.add(g.grantee)
  for (const t of m.tables) { for (const g of t.grants) rs.add(g.grantee); for (const p of t.policies) for (const r of p.roles) rs.add(r) }
  for (const f of m.functions) for (const r of f.execute.split(',').filter(Boolean)) rs.add(r)
  rs.delete('PUBLIC'); rs.delete('public')
  return [...rs].sort()
}

export function fixtureSql(m) {
  const o = []
  const p = (s) => o.push(s)
  const warnDo = (stmt, what) => p(`do $w$ begin execute ${dollar(stmt, 'st')}; exception when others then raise warning 'prod-parity fixture could not reproduce %: %', ${lit(what)}, sqlerrm; end $w$;`)
  const ifNoConstraint = (fq, c) => p(`do $c$ begin if not exists (select 1 from pg_constraint where conrelid = ${lit(qid(fq))}::regclass and conname = ${lit(c.name)}) then execute ${dollar(`alter table ${qid(fq)} add constraint ${qid(c.name)} ${c.def}`, 'st')}; end if; end $c$;`)
  p(`-- Generated by scripts/prod-parity-capture.mjs fixture from a ${m.tool} manifest (server ${m.server_version_num}). Isolated local PostgreSQL only.`)
  p(`-- Scope: tables ${m.scope.tables.join(', ') || '-'}; functions ${m.scope.functions.join(', ') || '-'}; lookups ${m.scope.lookups.join(', ') || '-'}.`)
  p(`do $g$ begin if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then raise exception 'prod-parity fixtures are for a local database only'; end if;`)
  p(`  if exists (select 1 from pg_namespace where nspname = 'supabase_migrations') and exists (select 1 from pg_roles where rolname = 'supabase_admin') then raise exception 'refusing a Supabase project database'; end if; end $g$;`)
  p('set check_function_bodies = off;')
  p(`do $s$ begin execute format('alter database %I set search_path to ' || ${lit(m.search_path)}, current_database()); end $s$;`)
  p(`set search_path to ${m.search_path};`)
  for (const r of rolesUsed(m)) p(`do $r$ begin create role ${role(r)} nologin; exception when duplicate_object then null; end $r$;`)
  for (const r of m.roles) {
    p(`do $r$ begin execute format('alter role ${role(r.name)} in database %I reset all', current_database()); end $r$;`)
    for (const kv of (r.settings || '').split(',').filter(Boolean)) {
      const [k, v] = [kv.slice(0, kv.indexOf('=')), kv.slice(kv.indexOf('=') + 1)]
      p(`do $r$ begin execute format('alter role ${role(r.name)} in database %I set ${k} = %L', current_database(), ${lit(v)}); end $r$;`)
    }
  }
  const schemas = new Set([...m.tables.map((t) => t.fq.split('.')[0]), ...m.functions.map((f) => f.sig.split('.')[0]), ...m.types.map((t) => t.name.includes('.') ? t.name.split('.')[0] : null).filter(Boolean)])
  for (const s of [...schemas].sort()) p(`create schema if not exists ${qid(s)};`)
  for (const s of [...schemas].sort()) p(`revoke all on schema ${qid(s)} from ${['public', ...rolesUsed(m).map(role)].join(', ')};`)
  for (const g of m.schemas || []) for (const pr of g.privileges.split(',')) p(`grant ${pr.replace('*', '').toLowerCase()} on schema ${qid(g.name)} to ${role(g.grantee)}${pr.endsWith('*') ? ' with grant option' : ''};`)
  for (const t of m.types) {
    if (t.typtype === 'e') p(`do $t$ begin create type ${t.name} as enum (${t.labels.map(lit).join(', ')}); exception when duplicate_object then null; end $t$;`)
    else p(`do $t$ begin create domain ${t.name} as ${t.base} ${(t.checks || []).join(' ')}; exception when duplicate_object then null; end $t$;`)
  }
  const seqs = new Set()
  for (const t of m.tables) for (const c of t.columns) for (const x of String(c.default || '').matchAll(/nextval\('([^']+)'::regclass\)/g)) seqs.add(x[1])
  for (const s of [...seqs].sort()) p(`create sequence if not exists ${s};`)
  // 1 tables and columns (lookups, then referenced, then targets)
  for (const t of m.tables) {
    p(`create table if not exists ${qid(t.fq)} ();`)
    for (const c of t.columns) {
      const gen = c.generated === 's' ? ` generated always as (${c.default}) stored` : c.identity ? ` generated ${c.identity === 'a' ? 'always' : 'by default'} as identity` : ''
      p(`alter table ${qid(t.fq)} add column if not exists ${qid(c.name)} ${c.type}${gen};`)
    }
  }
  // 2 keys of every table
  for (const t of m.tables) for (const c of t.constraints.filter((x) => x.type === 'p' || x.type === 'u')) ifNoConstraint(t.fq, c)
  // 3 lookup rows (code values only)
  for (const t of m.tables.filter((x) => x.kind === 'lookup')) {
    if (t.refused) { p(`-- ${t.fq}: ${t.refused}; no rows seeded`); continue }
    if (!t.rows?.length) continue
    const cols = t.columns.filter((c) => c.generated !== 's').map((c) => qid(c.name)).join(', ')
    const over = t.columns.some((c) => c.identity === 'a') ? ' overriding system value' : ''
    p(`insert into ${qid(t.fq)} (${cols})${over} select ${cols} from jsonb_populate_recordset(null::${qid(t.fq)}, ${dollar(JSON.stringify(t.rows), 'rows')}::jsonb) on conflict do nothing;`)
  }
  // 4 functions (definitions as captured; bodies are not validated here)
  for (const f of m.functions) p(f.def.trimEnd() + ';')
  // 5 not null and defaults (a default that needs an object outside the scope is reported, and the check lists it)
  for (const t of m.tables) for (const c of t.columns) {
    if (c.not_null) p(`alter table ${qid(t.fq)} alter column ${qid(c.name)} set not null;`)
    if (c.default != null && c.generated !== 's' && !c.identity) warnDo(`alter table ${qid(t.fq)} alter column ${qid(c.name)} set default ${c.default}`, `default of ${t.fq}.${c.name}`)
  }
  // 6 check, foreign-key and exclusion constraints; indexes
  for (const t of m.tables.filter((x) => x.kind === 'target')) for (const c of t.constraints.filter((x) => ['c', 'f', 'x'].includes(x.type))) ifNoConstraint(t.fq, c)
  for (const t of m.tables) for (const i of t.indexes) p(i.def.replace(/^CREATE (UNIQUE )?INDEX /, (_, u) => `CREATE ${u || ''}INDEX IF NOT EXISTS `) + ';')
  // 7 triggers
  for (const t of m.tables) for (const g of t.triggers) {
    p(`drop trigger if exists ${qid(g.name)} on ${qid(t.fq)};`)
    p(g.def + ';')
    const st = { D: 'disable', R: 'enable replica', A: 'enable always' }[g.enabled]
    if (st) p(`alter table ${qid(t.fq)} ${st} trigger ${qid(g.name)};`)
  }
  // 8 RLS and policies
  for (const t of m.tables) {
    p(`alter table ${qid(t.fq)} ${t.rls ? 'enable' : 'disable'} row level security;`)
    p(`alter table ${qid(t.fq)} ${t.force_rls ? 'force' : 'no force'} row level security;`)
    for (const pol of t.policies) {
      p(`drop policy if exists ${qid(pol.name)} on ${qid(t.fq)};`)
      p(`create policy ${qid(pol.name)} on ${qid(t.fq)} as ${pol.permissive ? 'permissive' : 'restrictive'} for ${CMD[pol.cmd]} to ${pol.roles.map(role).join(', ')}${pol.using != null ? ` using (${pol.using})` : ''}${pol.check != null ? ` with check (${pol.check})` : ''};`)
    }
  }
  // 9 grants: exactly what production grants, nothing more
  const everyone = ['public', ...rolesUsed(m).map(role)].join(', ')
  for (const t of m.tables.filter((x) => x.kind === 'target')) {
    p(`revoke all on table ${qid(t.fq)} from ${everyone};`)
    for (const g of t.grants) {
      const plain = g.privileges.split(',').filter((x) => !x.endsWith('*'))
      const opt = g.privileges.split(',').filter((x) => x.endsWith('*')).map((x) => x.slice(0, -1))
      for (const [privs, w] of [[plain, ''], [opt, ' with grant option']]) for (const pr of privs) {
        const stmt = `grant ${pr.toLowerCase()} on table ${qid(t.fq)} to ${role(g.grantee)}${w}`
        if (pr === 'MAINTAIN') warnDo(stmt, `MAINTAIN on ${t.fq} (PostgreSQL 17)`); else p(stmt + ';')
      }
    }
  }
  for (const f of m.functions) {
    p(`revoke all on function ${f.sig} from ${everyone};`)
    for (const r of f.execute.split(',').filter(Boolean)) p(`grant execute on function ${f.sig} to ${role(r)};`)
  }
  p(`do $d$ begin raise notice 'prod-parity fixture: % tables, % functions reproduced; run check-sql to confirm', ${m.tables.length}, ${m.functions.length}; end $d$;`)
  return o.join('\n') + '\n'
}

export function checkSql(m) {
  const capture = captureSql(m.scope).trimEnd()
  return `with expected(k, v) as (select key, value from jsonb_each_text(${dollar(JSON.stringify(m.facts), 'facts')}::jsonb)),
actual(k, v) as (select key, value from jsonb_each_text((select q.manifest from (
${capture}
) q)->'facts'))
select coalesce(e.k, a.k) as fact, case when a.k is null then 'missing' when e.k is null then 'unexpected' else 'different' end as diff,
       e.v as expected, a.v as actual
  from expected e full join actual a on a.k = e.k
 where e.v is distinct from a.v
 order by 1
`
}

// A manifest restricted to some of its target tables (with the tables they reference, the lookups they use and their functions), so a
// fixture that holds only part of the scope can be checked. The facts kept are exactly those a capture of the smaller scope produces.
export function subsetManifest(m, keepTables, keepFunctions = []) {
  const targets = m.tables.filter((t) => t.kind === 'target' && keepTables.includes(t.fq))
  if (targets.length !== keepTables.length) throw Error(`not target tables of this manifest: ${keepTables.filter((x) => !targets.some((t) => t.fq === x)).join(', ')}`)
  const refd = new Set(targets.flatMap((t) => t.constraints.filter((c) => c.type === 'f').map((c) => c.def.match(/REFERENCES ([^(]+)\(/)[1])))
  const tables = m.tables.filter((t) => targets.includes(t) || (t.kind !== 'target' && refd.has(t.fq)))
  const lookups = tables.filter((t) => t.kind === 'lookup').map((t) => t.fq)
  const needed = new Set([...targets.flatMap((t) => t.triggers.map((g) => g.function)), ...keepFunctions])
  const deps = m.functions.filter((f) => f.kind === 'dependency').map((f) => f.sig)
  const functions = m.functions.filter((f) => needed.has(f.sig) || (f.kind === 'dependency' && deps.includes(f.sig) && targets.some((t) => JSON.stringify(t).includes(f.sig.replace(/\(.*$/, '')))))
  const fqs = new Set(tables.map((t) => t.fq)); const sigs = new Set(functions.map((f) => f.sig))
  const nsps = new Set([...fqs, ...sigs].map((x) => x.split('.')[0]))
  const facts = Object.fromEntries(Object.entries(m.facts).filter(([k]) => {
    const [kind, a] = k.split('|')
    if (['table', 'column', 'constraint', 'index', 'trigger', 'policy', 'grant', 'lookup_rows'].includes(kind)) return fqs.has(a)
    if (kind === 'function' || kind === 'execute') return sigs.has(a)
    if (kind === 'schema') return nsps.has(a)
    if (kind === 'missing') return false
    return true
  }))
  const scope = { ...m.scope, tables: keepTables.slice().sort(), lookups: m.scope.lookups.filter((x) => lookups.includes(x)), functions: m.scope.functions.filter((x) => keepFunctions.includes(x)) }
  return { ...m, scope, tables, functions, facts, missing: [], subset_of: m.source || 'manifest' }
}

// The facts as one canonical text (sorted by byte order, key=value per line) and its md5: the digest check returns one row, so a short
// read on production says whether a manifest is still current; when it differs, run the full check to see what changed.
export function factsDigest(facts) {
  const keys = Object.keys(facts).sort((a, b) => (Buffer.from(a) < Buffer.from(b) ? -1 : Buffer.from(a) > Buffer.from(b) ? 1 : 0))
  return { facts: keys.length, md5: md5(keys.map((k) => `${k}=${facts[k]}`).join('\n')) }
}

export function digestSql(m) {
  const capture = captureSql(m.scope).trimEnd()
  const d = factsDigest(m.facts)
  return `select count(*) as facts, md5(string_agg(f.key || '=' || f.value, E'\\n' order by f.key collate "C")) as md5,
       count(*) = ${d.facts} and md5(string_agg(f.key || '=' || f.value, E'\\n' order by f.key collate "C")) = '${d.md5}' as matches_manifest
  from jsonb_each_text((select q.manifest from (
${capture}
) q)->'facts') f
`
}

export function diffFacts(a, b) {
  const out = []
  for (const k of [...new Set([...Object.keys(a.facts), ...Object.keys(b.facts)])].sort()) {
    if (a.facts[k] === b.facts[k]) continue
    out.push({ fact: k, diff: !(k in b.facts) ? 'missing' : !(k in a.facts) ? 'unexpected' : 'different', expected: a.facts[k] ?? null, actual: b.facts[k] ?? null })
  }
  return out
}

function args(argv) {
  const o = { _: [] }
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '--digest') o.digest = true
    else if (a.startsWith('--')) { const k = a.slice(2); o[k] = argv[i + 1]; i++ } else o._.push(a)
  }
  return o
}
const list = (v) => (v ? String(v).split(/[;\n]/).flatMap((x) => (x.includes('(') ? [x] : x.split(','))).map((x) => x.trim()).filter(Boolean) : [])

function main() {
  const [cmd, ...rest] = process.argv.slice(2)
  const a = args(rest)
  const read = (f) => JSON.parse(fs.readFileSync(f, 'utf8'))
  if (cmd === 'capture-sql') {
    const scope = a.scope ? read(a.scope) : { tables: list(a.tables), functions: list(a.functions), lookups: list(a.lookups), max_lookup_rows: a['max-lookup-rows'] ?? 500 }
    process.stdout.write(captureSql(scope))
  } else if (cmd === 'save') {
    const [raw, out] = a._
    const m = parseCaptured(fs.readFileSync(raw, 'utf8'))
    const problems = verifyManifest(m)
    if (problems.length) { console.error(problems.join('\n')); process.exit(1) }
    if (a.source) m.source = a.source
    fs.writeFileSync(out, JSON.stringify(m, null, 1) + '\n')
    console.error(`saved ${out}: ${m.tables.length} tables, ${m.functions.length} functions, ${Object.keys(m.facts).length} facts, missing ${m.missing.length}`)
  } else if (cmd === 'verify') {
    const m = read(a._[0]); const problems = verifyManifest(m)
    if (problems.length) { console.error(problems.join('\n')); process.exit(1) }
    console.log(`ok: ${Object.keys(m.facts).length} facts; definitions match their md5s`)
  } else if (cmd === 'fixture') {
    const m = read(a._[0]); const problems = verifyManifest(m)
    if (problems.length) { console.error(problems.join('\n')); process.exit(1) }
    process.stdout.write(fixtureSql(m))
  } else if (cmd === 'check-sql') {
    const m = read(a._[0])
    process.stdout.write(a.digest ? digestSql(m) : checkSql(m))
  } else if (cmd === 'subset') {
    const out = subsetManifest(read(a._[0]), list(a.tables), list(a.functions))
    process.stdout.write(JSON.stringify(out, null, 1) + '\n')
  } else if (cmd === 'diff') {
    const d = diffFacts(read(a._[0]), read(a._[1]))
    for (const r of d) console.log(`${r.diff}\t${r.fact}\n  expected: ${r.expected}\n  actual:   ${r.actual}`)
    console.log(d.length ? `${d.length} difference(s)` : 'parity: no differences')
    process.exit(d.length ? 1 : 0)
  } else {
    console.error(`usage:
  node scripts/prod-parity-capture.mjs capture-sql --tables a.b,c.d --functions 'security.f(uuid);security.g' --lookups pipeline.codes [--max-lookup-rows 500]
  node scripts/prod-parity-capture.mjs capture-sql --scope scope.json
  node scripts/prod-parity-capture.mjs save <tool-output.txt> <manifest.json> [--source "..."]
  node scripts/prod-parity-capture.mjs verify <manifest.json>
  node scripts/prod-parity-capture.mjs fixture <manifest.json> > fixture.sql
  node scripts/prod-parity-capture.mjs check-sql <manifest.json> > check.sql      (no rows = parity)
  node scripts/prod-parity-capture.mjs check-sql <manifest.json> --digest           (one row: matches_manifest)
  node scripts/prod-parity-capture.mjs subset <manifest.json> --tables pipeline.x[,..] [--functions ...] > part.json
  node scripts/prod-parity-capture.mjs diff <expected.json> <actual.json>`)
    process.exit(2)
  }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main()
