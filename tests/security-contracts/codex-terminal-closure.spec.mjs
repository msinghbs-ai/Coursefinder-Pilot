import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'

const read = filePath => fs.readFile(filePath, 'utf8')

async function readAllMigrations() {
  const dir = 'supabase/migrations'
  const names = (await fs.readdir(dir)).filter(name => name.endsWith('.sql')).sort()
  return (await Promise.all(names.map(async name => `\n-- ${name}\n${await read(`${dir}/${name}`)}`))).join('\n')
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

function hasNestedBlockComment(source) {
  let depth = 0
  let single = false
  let double = false
  let dollarTag = null
  for (let i = 0; i < source.length; i += 1) {
    const ch = source[i]
    const next = source[i + 1]
    if (dollarTag) {
      if (source.startsWith(dollarTag, i)) {
        i += dollarTag.length - 1
        dollarTag = null
      }
      continue
    }
    if (single) {
      if (ch === "'" && next === "'") i += 1
      else if (ch === "'") single = false
      continue
    }
    if (double) {
      if (ch === '"' && next === '"') i += 1
      else if (ch === '"') double = false
      continue
    }
    if (depth === 0) {
      if (ch === "'") { single = true; continue }
      if (ch === '"') { double = true; continue }
      const tag = source.slice(i).match(/^\$[A-Za-z_][A-Za-z0-9_]*\$|^\$\$/)?.[0]
      if (tag) { dollarTag = tag; i += tag.length - 1; continue }
    }
    if (ch === '/' && next === '*') {
      depth += 1
      if (depth > 1) return true
      i += 1
      continue
    }
    if (ch === '*' && next === '/' && depth > 0) {
      depth -= 1
      i += 1
    }
  }
  return false
}

function splitFunctionDefinitions(source) {
  return [...source.matchAll(/create\s+(?:or\s+replace\s+)?function\s+((?:"?[A-Za-z_][A-Za-z0-9_]*"?\s*\.\s*)?"?[A-Za-z_][A-Za-z0-9_]*"?)\s*\([^)]*\)([\s\S]*?)(?=\n\s*(?:create\s+(?:or\s+replace\s+)?function|drop\s+(?:function|routine)|alter\s+(?:function|routine))|$)/gi)]
}

const governedRoutine = '(?:svc_ranking_ingest_apply|provider_contact_profiles_claim_service|provider_contact_profile_finish_claim_service)'

test('platform rank guard uses the unmodified caller-rank result', async () => {
  const migrations = await readAllMigrations()
  const body = latestPlatformDefinition(migrations)
  expect(body).toBeTruthy()
  const guardIndex = body.search(/if\s+v_rank\s*<\s*4\s+then\s+raise\s+exception/i)
  expect(guardIndex).toBeGreaterThanOrEqual(0)
  const beforeGuard = body.slice(0, guardIndex)
  const direct = [...beforeGuard.matchAll(/v_rank\s*:=\s*([^;]+);/gi)].at(-1)
  const selected = [...beforeGuard.matchAll(/select\s+([^;]+?)\s+into\s+v_rank\s*;/gi)].at(-1)
  const directIndex = direct?.index ?? -1
  const selectIndex = selected?.index ?? -1
  const expression = directIndex > selectIndex ? direct?.[1] : selected?.[1]
  expect((expression || '').replace(/\s+/g, '')).toMatch(/^security\.current_role_rank\(\)$/i)
})

test('SECURITY DEFINER wrappers around service-only routines are not PUBLIC executable by default', async () => {
  const migrations = await readAllMigrations()
  for (const def of splitFunctionDefinitions(migrations)) {
    const body = def[2] || ''
    if (!/\bsecurity\s+definer\b/i.test(body)) continue
    if (!new RegExp(`\\b${governedRoutine}\\b`, 'i').test(body)) continue
    const name = def[1].replace(/"/g, '').replace(/\s+/g, '')
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    expect(migrations, `${name} must revoke PostgreSQL default PUBLIC execute`).toMatch(
      new RegExp(`\\brevoke\\s+(?:execute|all(?:\\s+privileges)?)\\s+on\\s+(?:function|routine)\\s+${escaped}[^;]*\\bfrom\\s+[^;]*\\bpublic\\b`, 'i'),
    )
    expect(migrations, `${name} must not be granted to browser roles`).not.toMatch(
      new RegExp(`\\bgrant\\s+(?:execute|all(?:\\s+privileges)?)\\s+on\\s+(?:function|routine)\\s+${escaped}[^;]*\\bto\\s+[^;]*\\b(?:anon|authenticated|public)\\b`, 'i'),
    )
  }
})

test('Vite HTML scripts remain inside the governed src tree', async () => {
  const html = await read('index.html')
  const scripts = [...html.matchAll(/<script\b[^>]*\bsrc=["']([^"']+)["'][^>]*>/gi)].map(match => match[1])
  expect(scripts.length).toBeGreaterThan(0)
  for (const src of scripts) {
    expect(src, `script source ${src} must remain under /src/`).toMatch(/^\/src\/[A-Za-z0-9_./-]+$/)
    expect(src).not.toMatch(/\.\./)
  }
})

test('migrations do not use nested SQL block comments that can desynchronise effective-state parsing', async () => {
  const migrations = await readAllMigrations()
  expect(hasNestedBlockComment(migrations)).toBe(false)
})

test('dynamic SQL stored in variables cannot hide governed ACL or evidence mutations', async () => {
  const migrations = await readAllMigrations()
  const assignment = /\b([A-Za-z_][A-Za-z0-9_]*)\s*:=\s*((?:format|concat)\s*\([\s\S]*?\))\s*;/gi
  for (const match of migrations.matchAll(assignment)) {
    const variable = match[1]
    const expression = match[2]
    const executePattern = new RegExp(`\\bexecute\\s+${variable}\\b`, 'i')
    const remainder = migrations.slice((match.index ?? 0) + match[0].length)
    if (!executePattern.test(remainder)) continue
    const sensitive = new RegExp(`\\b${governedRoutine}\\b|pipeline\\s*\\.\\s*evidence_artifacts|storage\\s*\\.\\s*objects`, 'i').test(expression)
    if (!sensitive) continue
    expect(expression, `dynamic SQL variable ${variable} touches governed boundaries`).not.toMatch(
      /\b(?:grant\s+(?:execute|all)|owner\s+to|delete\s+from|update|truncate|merge\s+into)\b[\s\S]*(?:anon|authenticated|public|evidence_artifacts|storage)/i,
    )
  }
})
