import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'

const read = filePath => fs.readFile(filePath, 'utf8')

async function readAllMigrations() {
  const dir = 'supabase/migrations'
  const names = (await fs.readdir(dir)).filter(name => name.endsWith('.sql')).sort()
  return (await Promise.all(names.map(async name => `\n-- ${name}\n${await read(`${dir}/${name}`)}`))).join('\n')
}

function stripSqlComments(source) {
  let out = ''
  let i = 0
  let single = false
  let double = false
  let dollarTag = null
  while (i < source.length) {
    const ch = source[i]
    const next = source[i + 1]
    if (dollarTag) {
      if (source.startsWith(dollarTag, i)) {
        out += dollarTag
        i += dollarTag.length
        dollarTag = null
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
    if (ch === "'") { single = true; out += ch; i += 1; continue }
    if (ch === '"') { double = true; out += ch; i += 1; continue }
    const tag = source.slice(i).match(/^\$[A-Za-z_][A-Za-z0-9_]*\$|^\$\$/)?.[0]
    if (tag) { dollarTag = tag; out += tag; i += tag.length; continue }
    out += ch
    i += 1
  }
  return out
}

function balancedCalls(source, calleePattern) {
  const calls = []
  const pattern = new RegExp(calleePattern, 'gi')
  for (const match of source.matchAll(pattern)) {
    const open = source.indexOf('(', match.index ?? 0)
    if (open < 0) continue
    let i = open + 1
    let depth = 0
    let quote = null
    let dollarTag = null
    while (i < source.length) {
      const ch = source[i]
      const next = source[i + 1]
      if (dollarTag) {
        if (source.startsWith(dollarTag, i)) { i += dollarTag.length; dollarTag = null } else i += 1
        continue
      }
      if (quote) {
        if (ch === quote && next === quote) { i += 2; continue }
        if (ch === quote) quote = null
        i += 1
        continue
      }
      if (ch === "'" || ch === '"' || ch === '`') { quote = ch; i += 1; continue }
      const tag = source.slice(i).match(/^\$[A-Za-z_][A-Za-z0-9_]*\$|^\$\$/)?.[0]
      if (tag) { dollarTag = tag; i += tag.length; continue }
      if (ch === '(' || ch === '[' || ch === '{') depth += 1
      if (ch === ')' || ch === ']' || ch === '}') {
        if (ch === ')' && depth === 0) { calls.push(source.slice(match.index ?? 0, i + 1)); break }
        depth -= 1
      }
      i += 1
    }
  }
  return calls
}

function latestPlatformDefinition(source) {
  const pattern = /create\s+(?:or\s+replace\s+)?function\s+(?:"security"|security)\s*\.\s*(?:"admin_platform_maturity_read"|admin_platform_maturity_read)\s*\(([^)]*)\)/gi
  const matches = [...source.matchAll(pattern)]
  const exact = matches.filter(match => /\btext\b/i.test(match[1]) && /\bjsonb\b/i.test(match[1])).at(-1)
  if (!exact) return ''
  const start = exact.index ?? 0
  const next = /\n\s*(?:create\s+(?:or\s+replace\s+)?function|drop\s+(?:function|routine)|alter\s+(?:function|routine))\b/gi
  next.lastIndex = start + exact[0].length
  const boundary = next.exec(source)
  return source.slice(start, boundary ? boundary.index : source.length)
}

const governedRoutine = '(?:svc_ranking_ingest_apply|provider_contact_profiles_claim_service|provider_contact_profile_finish_claim_service)'
const quotedBrowserRole = '(?:"?(?:anon|authenticated|public)"?)'

test('formatted or concatenated dynamic SQL cannot alter governed ACLs or evidence', async () => {
  const migrations = stripSqlComments(await readAllMigrations())
  const dynamicCalls = [
    ...balancedCalls(migrations, '\\bexecute\\s+format\\s*\\('),
    ...balancedCalls(migrations, '\\bexecute\\s+concat\\s*\\('),
  ]
  for (const call of dynamicCalls) {
    const sensitive = new RegExp(`\\b${governedRoutine}\\b|pipeline\\s*\\.\\s*evidence_artifacts|storage\\s*\\.\\s*objects`, 'i').test(call)
    if (!sensitive) continue
    expect(call, 'dynamic SQL touching governed boundaries must not grant browser access or mutate evidence')
      .not.toMatch(/\b(?:grant\s+(?:execute|all)|owner\s+to|delete\s+from|update|truncate|merge\s+into)\b[\s\S]*(?:anon|authenticated|public|evidence_artifacts|storage)/i)
  }

  expect(migrations).not.toMatch(new RegExp(`\\bexecute\\s+[^;\\n]+\\|\\|[^;\\n]*\\b${governedRoutine}\\b`, 'i'))
  expect(migrations).not.toMatch(/\bexecute\s+[^;\n]+\|\|[^;\n]*(?:pipeline\s*\.\s*evidence_artifacts|storage\s*\.\s*objects)/i)
})

test('quoted role identifiers cannot bypass ownership or role-inheritance boundaries', async () => {
  const migrations = stripSqlComments(await readAllMigrations())
  expect(migrations).not.toMatch(new RegExp(`\\balter\\s+(?:function|routine)\\s+[^;]*\\b${governedRoutine}\\b[^;]*\\bowner\\s+to\\s+${quotedBrowserRole}\\b`, 'i'))
  expect(migrations).not.toMatch(/\bgrant\s+"?service_role"?\s+to\s+[^;]*"?(?:anon|authenticated)"?\b/i)
})

test('platform rank guard uses caller rank as the guarded value', async () => {
  const migrations = stripSqlComments(await readAllMigrations())
  const body = latestPlatformDefinition(migrations)
  expect(body).toBeTruthy()
  const guardIndex = body.search(/if\s+v_rank\s*<\s*4\s+then\s+raise\s+exception/i)
  expect(guardIndex).toBeGreaterThanOrEqual(0)
  const beforeGuard = body.slice(0, guardIndex)
  const directAssignments = [...beforeGuard.matchAll(/v_rank\s*:=\s*([^;]+);/gi)]
  const selectAssignments = [...beforeGuard.matchAll(/select\s+([^;]+?)\s+into\s+v_rank\s*;/gi)]
  const latestDirect = directAssignments.at(-1)
  const latestSelect = selectAssignments.at(-1)
  const latestDirectIndex = latestDirect?.index ?? -1
  const latestSelectIndex = latestSelect?.index ?? -1
  expect(Math.max(latestDirectIndex, latestSelectIndex)).toBeGreaterThanOrEqual(0)
  const boundExpression = latestDirectIndex > latestSelectIndex ? latestDirect?.[1] : latestSelect?.[1]
  expect(boundExpression || '').toMatch(/security\s*\.\s*current_role_rank\s*\(/i)
})

test('governed evidence is protected from MERGE-based mutation', async () => {
  const migrations = stripSqlComments(await readAllMigrations())
  expect(migrations).not.toMatch(/\bmerge\s+into\s+(?:pipeline\s*\.\s*evidence_artifacts|storage\s*\.\s*objects)\b[\s\S]*?\bwhen\s+matched\b[\s\S]*?\bthen\s+(?:delete|update)\b/i)
})

test('ranking acquisition never fetches raw operator-provided URLs', async () => {
  const [qs, the] = await Promise.all([
    read('supabase/functions/ranking-qs-url-import/index.ts'),
    read('supabase/functions/ranking-the-url-import/index.ts'),
  ])
  for (const [name, source] of [['QS', qs], ['THE', the]]) {
    expect(source, `${name} must validate source_url before using it`).toMatch(/src\s*=\s*(?:validateUrl|validate)\s*\(/)
    for (const call of balancedCalls(source, '\\bfetch\\s*\\(')) {
      expect(call, `${name} outbound fetch must not use raw request/body source URL`).not.toMatch(/fetch\s*\(\s*(?:body|req|request|payload|json)\b[\s\S]*?(?:source_url|url)/i)
      expect(call, `${name} outbound fetch must not dereference source_url directly`).not.toMatch(/fetch\s*\([^)]*\.source_url\b/i)
    }
  }
})

test('browser-granted SECURITY DEFINER wrappers cannot call service-only governed routines', async () => {
  const migrations = stripSqlComments(await readAllMigrations())
  const defs = [...migrations.matchAll(/create\s+(?:or\s+replace\s+)?function\s+((?:"?[A-Za-z_][A-Za-z0-9_]*"?\s*\.\s*)?"?[A-Za-z_][A-Za-z0-9_]*"?)\s*\([^)]*\)([\s\S]*?)(?=\n\s*(?:create\s+(?:or\s+replace\s+)?function|drop\s+(?:function|routine)|alter\s+(?:function|routine))|$)/gi)]
  for (const def of defs) {
    const body = def[2] || ''
    if (!/\bsecurity\s+definer\b/i.test(body)) continue
    if (!new RegExp(`\\b${governedRoutine}\\b`, 'i').test(body)) continue
    const name = def[1].replace(/"/g, '').replace(/\s+/g, '')
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    expect(migrations, `${name} wraps a service-only routine and must not be browser executable`).not.toMatch(new RegExp(`\\bgrant\\s+(?:execute|all(?:\\s+privileges)?)\\s+on\\s+(?:function|routine)\\s+${escaped}[^;]*\\bto\\s+[^;]*"?(?:anon|authenticated|public)"?\\b`, 'i'))
  }
})

test('Vite HTML entry point cannot bypass the central browser Supabase boundary', async () => {
  const html = await read('index.html')
  expect(html).not.toMatch(/SUPABASE_SERVICE(?:_ROLE)?(?:_KEY)?|service[_-]?role/i)
  expect(html).not.toMatch(/@supabase\/supabase-js/i)
  expect(html).not.toMatch(/\bcreateClient\s*\(/i)
  expect(html).not.toMatch(/<script[^>]+src=["'][^"']*(?:\.\.\/|^\/)(?!src\/)/i)
})
