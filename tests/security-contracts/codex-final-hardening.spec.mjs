import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'

const read = filePath => fs.readFile(filePath, 'utf8')

async function readAllMigrations() {
  const dir = 'supabase/migrations'
  const names = (await fs.readdir(dir)).filter(name => name.endsWith('.sql')).sort()
  return (await Promise.all(names.map(name => read(`${dir}/${name}`)))).join('\n')
}

function stripSqlComments(source) {
  let out = ''
  let i = 0
  let single = false
  let double = false
  let dollar = null
  while (i < source.length) {
    const ch = source[i]
    const next = source[i + 1]
    if (dollar) {
      if (source.startsWith(dollar, i)) {
        out += dollar
        i += dollar.length
        dollar = null
      } else {
        out += ch
        i += 1
      }
      continue
    }
    if (single) {
      out += ch
      if (ch === "'" && next === "'") {
        out += next
        i += 2
      } else {
        if (ch === "'") single = false
        i += 1
      }
      continue
    }
    if (double) {
      out += ch
      if (ch === '"' && next === '"') {
        out += next
        i += 2
      } else {
        if (ch === '"') double = false
        i += 1
      }
      continue
    }
    if (ch === '-' && next === '-') {
      const end = source.indexOf('\n', i + 2)
      const stop = end < 0 ? source.length : end
      out += ' '.repeat(stop - i)
      i = stop
      continue
    }
    if (ch === '/' && next === '*') {
      const end = source.indexOf('*/', i + 2)
      const stop = end < 0 ? source.length : end + 2
      out += ' '.repeat(stop - i)
      i = stop
      continue
    }
    if (ch === "'") {
      single = true
      out += ch
      i += 1
      continue
    }
    if (ch === '"') {
      double = true
      out += ch
      i += 1
      continue
    }
    const tag = source.slice(i).match(/^\$[A-Za-z_][A-Za-z0-9_]*\$|^\$\$/)?.[0]
    if (tag) {
      dollar = tag
      out += tag
      i += tag.length
      continue
    }
    out += ch
    i += 1
  }
  return out
}

function constantDynamicSql(source) {
  const sql = stripSqlComments(source)
  const values = []
  for (const match of sql.matchAll(/\bexecute\s+'((?:''|[^'])*)'/gi)) values.push(match[1].replace(/''/g, "'"))
  for (const match of sql.matchAll(/\bexecute\s+(\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$)([\s\S]*?)\1/gi)) values.push(match[2])
  return values.join('\n')
}

function maskJsLiteralsAndComments(source) {
  let out = ''
  let i = 0
  let quote = null
  let line = false
  let block = false
  while (i < source.length) {
    const ch = source[i]
    const next = source[i + 1]
    if (line) {
      if (ch === '\n') { line = false; out += '\n' } else out += ' '
      i += 1
      continue
    }
    if (block) {
      if (ch === '*' && next === '/') { out += '  '; i += 2; block = false } else { out += ch === '\n' ? '\n' : ' '; i += 1 }
      continue
    }
    if (quote) {
      if (ch === '\\' && i + 1 < source.length) { out += '  '; i += 2; continue }
      if (ch === quote) { out += ' '; quote = null; i += 1; continue }
      out += ch === '\n' ? '\n' : ' '
      i += 1
      continue
    }
    if (ch === '/' && next === '/') { out += '  '; i += 2; line = true; continue }
    if (ch === '/' && next === '*') { out += '  '; i += 2; block = true; continue }
    if (ch === "'" || ch === '"' || ch === '`') { quote = ch; out += ' '; i += 1; continue }
    out += ch
    i += 1
  }
  return out
}

function callArguments(source, callee) {
  const calls = []
  const pattern = new RegExp(`\\b${callee}\\s*\\(`, 'g')
  for (const match of source.matchAll(pattern)) {
    const open = (match.index ?? 0) + match[0].lastIndexOf('(')
    let i = open + 1
    let depth = 0
    let current = ''
    const args = []
    while (i < source.length) {
      const ch = source[i]
      if (ch === '(' || ch === '[' || ch === '{') depth += 1
      if (ch === ')' || ch === ']' || ch === '}') {
        if (ch === ')' && depth === 0) { args.push(current.trim()); calls.push(args); break }
        depth -= 1
      }
      if (ch === ',' && depth === 0) { args.push(current.trim()); current = ''; i += 1; continue }
      current += ch
      i += 1
    }
  }
  return calls
}

const browserRole = '(?:anon|authenticated|public)'
const governedRoutine = '(?:svc_ranking_ingest_apply|provider_contact_profiles_claim_service|provider_contact_profile_finish_claim_service)'

test('governed routines reject dynamic ACL bypass, browser-role ownership and role inheritance', async () => {
  const migrations = await readAllMigrations()
  const executable = stripSqlComments(migrations)
  const dynamic = constantDynamicSql(migrations)
  const inspect = `${executable}\n${dynamic}`

  expect(inspect).not.toMatch(new RegExp(`\\bgrant\\s+(?:execute|all(?:\\s+privileges)?)\\s+on\\s+(?:function|routine)\\s+[^;]*\\b${governedRoutine}\\b[^;]*\\bto\\s+[^;]*\\b${browserRole}\\b`, 'i'))
  expect(inspect).not.toMatch(new RegExp(`\\balter\\s+(?:function|routine)\\s+[^;]*\\b${governedRoutine}\\b[^;]*\\bowner\\s+to\\s+${browserRole}\\b`, 'i'))
  expect(inspect).not.toMatch(new RegExp(`\\bgrant\\s+service_role\\s+to\\s+[^;]*\\b(?:anon|authenticated)\\b`, 'i'))
})

test('schema-wide ACLs cannot expose public governed routines through comma-separated schema lists', async () => {
  const migrations = stripSqlComments(await readAllMigrations())
  for (const match of migrations.matchAll(/\bgrant\s+(?:execute|all(?:\s+privileges)?)\s+on\s+all\s+(?:functions|routines)\s+in\s+schema\s+([^;]+?)\s+to\s+([^;]+)(?:;|$)/gi)) {
    const schemas = match[1].split(',').map(value => value.trim().replaceAll('"', '').toLowerCase())
    const roles = match[2].split(',').map(value => value.trim().replaceAll('"', '').toLowerCase())
    if (schemas.includes('public')) expect(roles.every(role => role === 'service_role')).toBe(true)
  }
})

test('global default EXECUTE privileges cannot make browser roles inherit governed routine execution', async () => {
  const migrations = stripSqlComments(await readAllMigrations())
  expect(migrations).not.toMatch(/alter\s+default\s+privileges(?![^;]*\bin\s+schema\b)[^;]*\bgrant\s+(?:execute|all(?:\s+privileges)?)\s+on\s+(?:functions|routines)\s+to\s+[^;]*\b(?:anon|authenticated|public)\b/i)
})

test('search-path resets and omitted-signature ACLs cannot bypass governed routine checks', async () => {
  const migrations = stripSqlComments(await readAllMigrations())
  const resetIndex = Math.max(migrations.toLowerCase().lastIndexOf('reset search_path'), migrations.toLowerCase().lastIndexOf('set search_path to default'))
  if (resetIndex >= 0) {
    const tail = migrations.slice(resetIndex)
    expect(tail).not.toMatch(/create\s+(?:or\s+replace\s+)?function\s+(?:admin_platform_maturity_read|provider_contact_profiles_claim_service|provider_contact_profile_finish_claim_service)\b/i)
  }
  expect(migrations).not.toMatch(new RegExp(`\\bgrant\\s+(?:execute|all(?:\\s+privileges)?)\\s+on\\s+(?:function|routine)\\s+(?:public\\s*\\.\\s*)?${governedRoutine}(?!\\s*\\()[^;]*\\bto\\s+[^;]*\\b${browserRole}\\b`, 'i'))
})

test('multi-routine DROP statements cannot silently remove governed routed routines', async () => {
  const migrations = stripSqlComments(await readAllMigrations())
  for (const match of migrations.matchAll(/\bdrop\s+(?:function|routine)\s+(?:if\s+exists\s+)?([^;]+)(?:;|$)/gi)) {
    const targets = match[1].split(/,(?=\s*(?:"?[A-Za-z_][A-Za-z0-9_]*"?\s*\.)?"?[A-Za-z_][A-Za-z0-9_]*"?\s*\()/)
    if (targets.length > 1) {
      expect(targets.some(target => /\b(?:admin_platform_maturity_read|provider_contact_profiles_claim_service|provider_contact_profile_finish_claim_service)\b/i.test(target))).toBe(false)
    }
  }
})

test('dynamic SQL cannot destructively mutate governed evidence tables', async () => {
  const dynamic = constantDynamicSql(await readAllMigrations())
  expect(dynamic).not.toMatch(/\b(?:delete\s+from|update|truncate\s+(?:table\s+)?(?:only\s+)?)\s+(?:pipeline\s*\.\s*evidence_artifacts|storage\s*\.\s*objects)\b/i)
})

test('signed evidence URL TTL is validated only from executable JavaScript calls', async () => {
  const worker = await read('supabase/functions/ranking-evidence-export/index.ts')
  const executable = maskJsLiteralsAndComments(worker)
  const calls = callArguments(executable, 'createSignedUrl')
  expect(calls.length).toBeGreaterThan(0)
  for (const args of calls) expect(args[1]).toBe('300')
})

test('non-central browser modules cannot wildcard re-export Supabase client constructors', async () => {
  async function walk(dir) {
    const entries = await fs.readdir(dir, { withFileTypes: true })
    const files = []
    for (const entry of entries) {
      const filePath = `${dir}/${entry.name}`
      if (entry.isDirectory()) files.push(...await walk(filePath))
      else if (/\.[cm]?[jt]sx?$/i.test(entry.name)) files.push(filePath)
    }
    return files
  }
  for (const file of await walk('src')) {
    if (file === 'src/lib/supabase.ts') continue
    const source = await read(file)
    expect(maskJsLiteralsAndComments(source), file).not.toMatch(/\bexport\s*\*\s*from\s*["']@supabase\/supabase-js["']/i)
  }
})

test('platform operator guard remains bound to caller role-rank derivation', async () => {
  const migrations = stripSqlComments(await readAllMigrations())
  const definitions = [...migrations.matchAll(/create\s+(?:or\s+replace\s+)?function\s+security\s*\.\s*admin_platform_maturity_read\s*\(([^)]*)\)([\s\S]*?)(?=\n\s*(?:create\s+(?:or\s+replace\s+)?function|drop\s+(?:function|routine)|alter\s+(?:function|routine))|$)/gi)]
  const exact = definitions.filter(match => /\btext\b/i.test(match[1]) && /\bjsonb\b/i.test(match[1])).at(-1)
  expect(exact).toBeTruthy()
  const body = exact?.[2] || ''
  const rank = body.search(/security\s*\.\s*current_role_rank\s*\(/i)
  const guard = body.search(/if\s+v_rank\s*<\s*4\s+then\s+raise\s+exception/i)
  expect(rank).toBeGreaterThanOrEqual(0)
  expect(guard).toBeGreaterThan(rank)
  const between = body.slice(rank, guard)
  expect(between).not.toMatch(/\bv_rank\s*:=\s*(?!security\s*\.\s*current_role_rank\s*\()/i)
})
