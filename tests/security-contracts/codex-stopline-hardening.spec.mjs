import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'

const read = path => fs.readFile(path, 'utf8')

async function migrationFiles() {
  const dir = 'supabase/migrations'
  const names = (await fs.readdir(dir)).filter(name => name.endsWith('.sql')).sort()
  return Promise.all(names.map(async name => ({ name, text: await read(`${dir}/${name}`) })))
}

function stripSqlComments(source) {
  let out = ''
  let i = 0
  let single = false
  let double = false
  let dollar = null
  let line = false
  let blockDepth = 0
  while (i < source.length) {
    const ch = source[i]
    const next = source[i + 1]
    if (line) {
      if (ch === '\n') { line = false; out += '\n' } else out += ' '
      i += 1
      continue
    }
    if (blockDepth > 0) {
      if (ch === '/' && next === '*') { blockDepth += 1; out += '  '; i += 2; continue }
      if (ch === '*' && next === '/') { blockDepth -= 1; out += '  '; i += 2; continue }
      out += ch === '\n' ? '\n' : ' '
      i += 1
      continue
    }
    if (dollar) {
      if (source.startsWith(dollar, i)) { out += dollar; i += dollar.length; dollar = null } else { out += ch; i += 1 }
      continue
    }
    if (single) {
      out += ch
      if (ch === "'" && next === "'") { out += next; i += 2; continue }
      if (ch === "'") single = false
      i += 1
      continue
    }
    if (double) {
      out += ch
      if (ch === '"' && next === '"') { out += next; i += 2; continue }
      if (ch === '"') double = false
      i += 1
      continue
    }
    if (ch === '-' && next === '-') { line = true; out += '  '; i += 2; continue }
    if (ch === '/' && next === '*') { blockDepth = 1; out += '  '; i += 2; continue }
    if (ch === "'") { single = true; out += ch; i += 1; continue }
    if (ch === '"') { double = true; out += ch; i += 1; continue }
    const tag = source.slice(i).match(/^\$[A-Za-z_][A-Za-z0-9_]*\$|^\$\$/)?.[0]
    if (tag) { dollar = tag; out += tag; i += tag.length; continue }
    out += ch
    i += 1
  }
  return out
}

function latestFunction(source, qualifiedName) {
  const escaped = qualifiedName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace('\\.', '\\s*\\.\\s*')
  const pattern = new RegExp(`create\\s+(?:or\\s+replace\\s+)?function\\s+${escaped}\\s*\\(([^)]*)\\)`, 'gi')
  const matches = [...source.matchAll(pattern)]
  if (!matches.length) return ''
  const match = matches.at(-1)
  const start = match.index ?? 0
  const boundary = /\n\s*(?:create\s+(?:or\s+replace\s+)?function|drop\s+(?:function|routine)|alter\s+(?:function|routine))\b/gi
  boundary.lastIndex = start + match[0].length
  const next = boundary.exec(source)
  return source.slice(start, next ? next.index : source.length)
}

function normaliseExpression(value) {
  return value.replace(/\s+/g, '').replace(/^\((.*)\)$/s, '$1')
}

function normaliseRoutineName(value) {
  return value.replace(/"/g, '').replace(/\s+/g, '').toLowerCase()
}

function normaliseSignature(value) {
  return value
    .split(',')
    .map(part => part.trim().replace(/\s+/g, ' ').toLowerCase())
    .join(',')
}

function routineKey(name, signature) {
  return `${normaliseRoutineName(name)}(${normaliseSignature(signature)})`
}

function functionDefinitions(source) {
  return [...source.matchAll(/create\s+(?:or\s+replace\s+)?function\s+((?:"?[A-Za-z_][A-Za-z0-9_]*"?\s*\.\s*)?"?[A-Za-z_][A-Za-z0-9_]*"?)\s*\(([^)]*)\)([\s\S]*?)(?=\n\s*(?:create\s+(?:or\s+replace\s+)?function|drop\s+(?:function|routine)|alter\s+(?:function|routine))|$)/gi)]
}

function parseScriptSources(html) {
  const sources = []
  for (const tag of html.match(/<script\b[^>]*>/gi) || []) {
    const match = tag.match(/\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i)
    if (match) sources.push(match[1] ?? match[2] ?? match[3] ?? '')
  }
  return sources
}

function serviceRoleMembershipExposure(source) {
  const hits = []
  for (const match of source.matchAll(/\bgrant\s+([^;]+?)\s+to\s+([^;]+?)(?:;|$)/gi)) {
    const granted = match[1].split(',').map(x => x.trim().replace(/^"|"$/g, '').toLowerCase())
    const recipientClause = match[2].replace(/\s+with\s+(?:admin|inherit|set)\b[\s\S]*$/i, '').trim()
    const recipients = recipientClause.split(',').map(x => x.trim().replace(/^"|"$/g, '').toLowerCase())
    if (granted.includes('service_role') && recipients.some(x => x === 'anon' || x === 'authenticated')) hits.push(match[0])
  }
  return hits
}

function dynamicVariableExecutions(source) {
  const results = []
  const assignment = /\b([A-Za-z_][A-Za-z0-9_]*)\s*(?::=|=)\s*((?:format|concat)\s*\([\s\S]*?\))\s*;/gi
  for (const match of source.matchAll(assignment)) {
    const remainder = source.slice((match.index ?? 0) + match[0].length)
    if (new RegExp(`\\bexecute\\s+${match[1]}\\b`, 'i').test(remainder)) results.push({ variable: match[1], expression: match[2] })
  }
  return results
}

function allSignedUrlTtls(source) {
  const ttls = []
  for (const match of source.matchAll(/\bcreateSignedUrl\s*\(\s*[^,]+,\s*([^,)]+)[,)]/g)) ttls.push(match[1].trim())
  return ttls
}

function activeSecurityDefinerWrappers(source) {
  const defs = functionDefinitions(source)
    .filter(def => /\bsecurity\s+definer\b/i.test(def[3] || '') && new RegExp(`\\b${governedRoutine}\\b`, 'i').test(def[3] || ''))
  const latest = new Map()
  for (const def of defs) latest.set(routineKey(def[1], def[2]), def)

  const active = []
  for (const [key, def] of latest) {
    const name = normaliseRoutineName(def[1])
    const signature = normaliseSignature(def[2])
    const tail = source.slice((def.index ?? 0) + def[0].length)
    let dropped = false
    for (const drop of tail.matchAll(/\bdrop\s+(?:function|routine)\s+([^;]+?)(?:;|$)/gi)) {
      for (const target of drop[1].split(/,(?![^()]*\))/)) {
        const parsed = target.trim().match(/^((?:"?[A-Za-z_][A-Za-z0-9_]*"?\s*\.\s*)?"?[A-Za-z_][A-Za-z0-9_]*"?)\s*\(([^)]*)\)/i)
        if (parsed && routineKey(parsed[1], parsed[2]) === key) dropped = true
      }
    }
    if (!dropped) active.push({ key, name, signature, def })
  }
  return active
}

function hasEffectivePublicRevokeAfter(source, wrapper) {
  const tail = source.slice((wrapper.def.index ?? 0) + wrapper.def[0].length)
  for (const revoke of tail.matchAll(/\brevoke\s+(?:execute|all(?:\s+privileges)?)\s+on\s+(?:function|routine)\s+([^;]+?)\s+from\s+([^;]+?)(?:;|$)/gi)) {
    const recipients = revoke[2].split(',').map(value => value.trim().replace(/^"|"$/g, '').toLowerCase())
    if (!recipients.includes('public')) continue
    for (const target of revoke[1].split(/,(?![^()]*\))/)) {
      const parsed = target.trim().match(/^((?:"?[A-Za-z_][A-Za-z0-9_]*"?\s*\.\s*)?"?[A-Za-z_][A-Za-z0-9_]*"?)\s*\(([^)]*)\)/i)
      if (parsed && routineKey(parsed[1], parsed[2]) === wrapper.key) return true
    }
  }
  return false
}

function latestDefinitionsByName(source) {
  const byName = new Map()
  for (const def of functionDefinitions(source)) {
    const name = normaliseRoutineName(def[1])
    const list = byName.get(name) || []
    list.push(def)
    byName.set(name, list)
  }
  return byName
}

function calledRoutineNames(body, knownNames) {
  const calls = new Set()
  for (const match of body.matchAll(/\b((?:[A-Za-z_][A-Za-z0-9_]*\.)?[A-Za-z_][A-Za-z0-9_]*)\s*\(/g)) {
    const name = match[1].toLowerCase()
    const qualified = knownNames.has(name) ? name : [...knownNames].find(candidate => candidate.endsWith(`.${name}`))
    if (qualified) calls.add(qualified)
  }
  return calls
}

function assertNoTransitiveEvidenceMutation(rootBody, definitionsByName, label) {
  const destructive = new RegExp(`\\b(?:delete\\s+from\\s+(?:only\\s+)?|update\\s+(?:only\\s+)?|truncate\\s+(?:table\\s+)?(?:only\\s+)?|merge\\s+into\\s+)${evidenceTables}\\b`, 'i')
  const visited = new Set()
  const visit = (name, body) => {
    const visitKey = `${name}:${body}`
    if (visited.has(visitKey)) return
    visited.add(visitKey)
    expect(body, `${label} -> ${name} must not mutate governed evidence`).not.toMatch(destructive)
    for (const called of calledRoutineNames(body, new Set(definitionsByName.keys()))) {
      for (const def of definitionsByName.get(called) || []) visit(called, def[3] || '')
    }
  }
  visit(label, rootBody)
}

const evidenceTables = '(?:pipeline\\s*\\.\\s*evidence_artifacts|storage\\s*\\.\\s*objects)'
const governedRoutine = '(?:svc_ranking_ingest_apply|provider_contact_profiles_claim_service|provider_contact_profile_finish_claim_service)'

test('platform rank definition is comment-free and bound exactly to caller rank', async () => {
  const source = stripSqlComments((await migrationFiles()).map(x => x.text).join('\n'))
  const body = latestFunction(source, 'security.admin_platform_maturity_read')
  expect(body).toBeTruthy()
  const guard = body.search(/if\s+v_rank\s*<\s*4\s+then\s+raise\s+exception/i)
  expect(guard).toBeGreaterThanOrEqual(0)
  const before = body.slice(0, guard)
  const direct = [...before.matchAll(/v_rank\s*:=\s*([^;]+);/gi)].at(-1)
  const selected = [...before.matchAll(/select\s+([^;]+?)\s+into\s+v_rank\s*;/gi)].at(-1)
  const chosen = (direct?.index ?? -1) > (selected?.index ?? -1) ? direct?.[1] : selected?.[1]
  expect(normaliseExpression(chosen || '')).toBe('security.current_role_rank()')
})

test('active SECURITY DEFINER wrappers revoke PUBLIC for each exact overload signature', async () => {
  const source = stripSqlComments((await migrationFiles()).map(x => x.text).join('\n'))
  for (const wrapper of activeSecurityDefinerWrappers(source)) {
    expect(hasEffectivePublicRevokeAfter(source, wrapper), `${wrapper.key} must revoke default PUBLIC execute after its latest definition`).toBe(true)
  }
})

test('all HTML script sources are parsed regardless of quoting and stay under /src/', async () => {
  const scripts = parseScriptSources(await read('index.html'))
  expect(scripts.length).toBeGreaterThan(0)
  for (const src of scripts) {
    expect(src).toMatch(/^\/src\/[A-Za-z0-9_./-]+$/)
    expect(src).not.toContain('..')
  }
})

test('stored dynamic SQL recognises both PLpgSQL assignment operators and fails closed on governed effects', async () => {
  const source = (await migrationFiles()).map(x => x.text).join('\n')
  for (const { variable, expression } of dynamicVariableExecutions(source)) {
    if (!new RegExp(`\\b${governedRoutine}\\b|${evidenceTables}`, 'i').test(expression)) continue
    expect(expression, `${variable} executes SQL touching governed boundaries`).not.toMatch(/\b(?:grant\s+(?:execute|all)|owner\s+to|delete\s+from|update|truncate|merge\s+into)\b[\s\S]*(?:anon|authenticated|public|evidence_artifacts|storage)/i)
  }
})

test('central browser Supabase constructor uses only the publishable key binding', async () => {
  const source = await read('src/lib/supabase.ts')
  expect(source).toMatch(/const\s+key\s*=\s*import\.meta\.env\.VITE_SUPABASE_PUBLISHABLE_KEY\b/)
  const call = source.match(/createClient\s*\(\s*([^,]+),\s*([^,]+),/s)
  expect(call).not.toBeNull()
  expect((call?.[1] || '').replace(/\s+/g, '')).toMatch(/^url(?:\?\?'')?$/)
  expect((call?.[2] || '').replace(/\s+/g, '')).toMatch(/^key(?:\?\?'')?$/)
})

test('effective governed routines and their helper call graph remain non-destructive to evidence', async () => {
  const source = stripSqlComments((await migrationFiles()).map(x => x.text).join('\n'))
  const definitions = latestDefinitionsByName(source)
  for (const name of ['security.platform_capacity_snapshot_internal', 'public.provider_contact_profiles_claim_service', 'public.provider_contact_profile_finish_claim_service']) {
    const body = latestFunction(source, name)
    expect(body, `${name} must exist`).toBeTruthy()
    assertNoTransitiveEvidenceMutation(body, definitions, name)
  }
})

test('service_role cannot be inherited by browser roles through role lists or membership options', async () => {
  const source = stripSqlComments((await migrationFiles()).map(x => x.text).join('\n'))
  expect(serviceRoleMembershipExposure(source)).toEqual([])
})

test('provider-contact claim update consumes the candidate CTE that owns FOR UPDATE SKIP LOCKED', async () => {
  const source = stripSqlComments((await migrationFiles()).map(x => x.text).join('\n'))
  const body = latestFunction(source, 'public.provider_contact_profiles_claim_service')
  expect(body).toBeTruthy()
  const ctes = body.match(/\bwith\s+candidate_ids\s+as\s*\(([\s\S]*?)\)\s*,\s*claimed\s+as\s*\(([\s\S]*?)\)\s*,\s*base\s+as\s*\(/i)
  expect(ctes, 'claim function must define candidate_ids then claimed CTEs').not.toBeNull()
  const candidate = ctes?.[1] || ''
  const claimed = ctes?.[2] || ''
  expect(candidate).toMatch(/\bselect\s+pcp\.id\b[\s\S]*\bfrom\s+pipeline\.provider_contact_profiles\s+pcp\b/i)
  expect(candidate).toMatch(/\bfor\s+update\s+of\s+pcp\s+skip\s+locked\b[\s\S]*\blimit\s+v_limit\b/i)
  expect(claimed).toMatch(/\bupdate\s+pipeline\.provider_contact_profiles\s+pcp\b[\s\S]*\bfrom\s+candidate_ids\s+c\b[\s\S]*\bwhere\s+pcp\.id\s*=\s*c\.id\b/i)
})

test('every signed evidence URL call is visible, remains 300 seconds, and is dominated by role-rank rejection', async () => {
  const source = await read('supabase/functions/ranking-evidence-export/index.ts')
  const ttls = allSignedUrlTtls(source)
  expect(ttls.length).toBeGreaterThan(0)
  for (const ttl of ttls) expect(ttl).toBe('300')
  const guard = source.search(/if\s*\(\s*Number\s*\(\s*ctx\.role_rank\s*\|\|\s*0\s*\)\s*<\s*1\s*\)\s*return[\s\S]*?authorised_role_required/i)
  expect(guard).toBeGreaterThanOrEqual(0)
  for (const match of source.matchAll(/\bcreateSignedUrl\s*\(/g)) expect(match.index ?? -1).toBeGreaterThan(guard)
})

test('ranking URL workers persist and register raw evidence before downstream apply RPCs', async () => {
  for (const path of ['supabase/functions/ranking-qs-url-import/index.ts', 'supabase/functions/ranking-the-url-import/index.ts']) {
    const source = await read(path)
    const upload = source.indexOf('.storage.from("evidence").upload') >= 0 ? source.indexOf('.storage.from("evidence").upload') : source.indexOf(".storage.from('evidence').upload")
    const register = source.indexOf('svc_ranking_raw_evidence_register')
    expect(upload, `${path} evidence upload`).toBeGreaterThanOrEqual(0)
    expect(register, `${path} raw evidence registration`).toBeGreaterThan(upload)
    for (const apply of source.matchAll(/svc_ranking_(?:ingest_apply|import_apply|apply)\b/g)) expect(apply.index ?? -1).toBeGreaterThan(register)
  }
})
