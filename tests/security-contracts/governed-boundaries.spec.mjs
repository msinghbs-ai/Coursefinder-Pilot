import fs from 'node:fs/promises'
import path from 'node:path'
import { test, expect } from '@playwright/test'

const read = filePath => fs.readFile(filePath, 'utf8')

async function readAllMigrations() {
  const dir = 'supabase/migrations'
  const names = (await fs.readdir(dir)).filter(name => name.endsWith('.sql')).sort()
  const contents = await Promise.all(names.map(async name => `\n-- ${name}\n${await read(`${dir}/${name}`)}`))
  return contents.join('\n')
}

async function readSourceFiles(dir = 'src') {
  const entries = await fs.readdir(dir, { withFileTypes: true })
  const files = []
  for (const entry of entries) {
    const filePath = path.join(dir, entry.name)
    if (entry.isDirectory()) {
      files.push(...await readSourceFiles(filePath))
    } else if (/\.(?:[cm]?[jt]sx?|css|html)$/i.test(entry.name)) {
      files.push({ path: filePath.replaceAll('\\', '/'), content: await read(filePath) })
    }
  }
  return files
}

function stripLineAndBlockComments(source, lineMarker = '//', { dollarOpaque = true } = {}) {
  let out = ''
  let i = 0
  let quote = null
  let dollarTag = null

  while (i < source.length) {
    if (dollarTag && dollarOpaque) {
      if (source.startsWith(dollarTag, i)) {
        out += dollarTag
        i += dollarTag.length
        dollarTag = null
      } else {
        out += source[i++]
      }
      continue
    }

    if (quote) {
      const ch = source[i]
      out += ch
      if (ch === quote) {
        if (source[i + 1] === quote) {
          out += source[i + 1]
          i += 2
          continue
        }
        quote = null
      } else if (ch === '\\' && quote !== '`' && i + 1 < source.length) {
        out += source[i + 1]
        i += 2
        continue
      }
      i += 1
      continue
    }

    const dollar = source.slice(i).match(/^\$[A-Za-z_][A-Za-z0-9_]*\$|^\$\$/)
    if (dollar) {
      const tag = dollar[0]
      out += tag
      i += tag.length
      if (dollarOpaque) dollarTag = tag
      continue
    }

    const ch = source[i]
    if (ch === "'" || ch === '"' || ch === '`') {
      quote = ch
      out += ch
      i += 1
      continue
    }

    if (source.startsWith('/*', i)) {
      const end = source.indexOf('*/', i + 2)
      i = end < 0 ? source.length : end + 2
      continue
    }

    if (lineMarker && source.startsWith(lineMarker, i)) {
      const end = source.indexOf('\n', i + lineMarker.length)
      if (end < 0) break
      out += '\n'
      i = end + 1
      continue
    }

    out += ch
    i += 1
  }

  return out
}

const stripCodeComments = source => stripLineAndBlockComments(source, '//')
const stripSqlComments = source => stripLineAndBlockComments(source, '--')
const stripPlpgsqlComments = source => stripLineAndBlockComments(source, '--', { dollarOpaque: false })

function normaliseRoles(raw) {
  return raw
    .replace(/\bwith\s+grant\s+option\b[\s\S]*$/i, '')
    .split(',')
    .map(role => role.trim().replace(/^"|"$/g, '').toLowerCase())
    .filter(Boolean)
}

function effectiveIngestExecuteGrantees(rawSql) {
  const sql = stripSqlComments(rawSql)
  const events = []
  const privilege = '(?:execute|all(?:\\s+privileges)?)'
  const publicSchema = '(?:"public"|public)'
  const ingestFunction = '(?:"svc_ranking_ingest_apply"|svc_ranking_ingest_apply)'
  const qualifiedIngest = `${publicSchema}\\s*\\.\\s*${ingestFunction}`
  const patterns = [
    ['drop', new RegExp(`drop\\s+function\\s+(?:if\\s+exists\\s+)?${qualifiedIngest}\\b`, 'gi')],
    ['create_replace', new RegExp(`create\\s+or\\s+replace\\s+function\\s+${qualifiedIngest}\\b`, 'gi')],
    ['create', new RegExp(`create\\s+function\\s+${qualifiedIngest}\\b`, 'gi')],
    ['grant_function', new RegExp(`grant\\s+${privilege}\\s+on\\s+function\\s+${qualifiedIngest}\\b[\\s\\S]*?\\bto\\s+([^;]+);`, 'gi')],
    ['revoke_function', new RegExp(`revoke\\s+${privilege}\\s+on\\s+function\\s+${qualifiedIngest}\\b[\\s\\S]*?\\bfrom\\s+([^;]+);`, 'gi')],
    ['grant_schema', new RegExp(`grant\\s+${privilege}\\s+on\\s+all\\s+functions\\s+in\\s+schema\\s+${publicSchema}\\s+to\\s+([^;]+);`, 'gi')],
    ['revoke_schema', new RegExp(`revoke\\s+${privilege}\\s+on\\s+all\\s+functions\\s+in\\s+schema\\s+${publicSchema}\\s+from\\s+([^;]+);`, 'gi')],
  ]

  for (const [kind, pattern] of patterns) {
    for (const match of sql.matchAll(pattern)) {
      events.push({ kind, index: match.index ?? 0, roles: match[1] ? normaliseRoles(match[1]) : [] })
    }
  }
  events.sort((a, b) => a.index - b.index)

  const grantees = new Set()
  let exists = false
  for (const event of events) {
    if (event.kind === 'drop') {
      exists = false
      grantees.clear()
      continue
    }
    if (event.kind === 'create') {
      exists = true
      grantees.clear()
      grantees.add('public')
      continue
    }
    if (event.kind === 'create_replace') {
      if (!exists) {
        exists = true
        grantees.clear()
        grantees.add('public')
      }
      continue
    }
    if (!exists) continue

    if (event.kind === 'grant_function' || event.kind === 'grant_schema') {
      for (const role of event.roles) grantees.add(role)
    } else {
      for (const role of event.roles) grantees.delete(role)
    }
  }

  return [...grantees].sort()
}

function latestFunctionDefinition(rawSql, qualifiedName) {
  const sql = stripSqlComments(rawSql)
  const escaped = qualifiedName.split('.').map(part => `(?:"${part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}"|${part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})`).join('\\s*\\.\\s*')
  const definition = new RegExp(`create\\s+(?:or\\s+replace\\s+)?function\\s+${escaped}\\s*\\(`, 'gi')
  const matches = [...sql.matchAll(definition)]
  if (!matches.length) return ''
  const start = matches.at(-1).index ?? 0
  const nextPattern = /create\s+(?:or\s+replace\s+)?function\b/gi
  nextPattern.lastIndex = start + matches.at(-1)[0].length
  const next = nextPattern.exec(sql)
  return stripPlpgsqlComments(sql.slice(start, next ? next.index : sql.length))
}

test('QS and THE acquisition remain publisher-allowlisted and Evidence-first', async () => {
  const [qsRaw, theRaw] = await Promise.all([
    read('supabase/functions/ranking-qs-url-import/index.ts'),
    read('supabase/functions/ranking-the-url-import/index.ts'),
  ])
  const qs = stripCodeComments(qsRaw)
  const the = stripCodeComments(theRaw)

  expect(qs).toMatch(/if\s*\(\s*u\.protocol\s*!==\s*["']https:["']\s*\|\|\s*u\.hostname\s*!==\s*["']www\.topuniversities\.com["']\s*\)\s*throw/)
  expect(qs).toMatch(/world-university-rankings/)
  expect(qs).toContain('complete_qs_source_unavailable')
  expect(qs).toContain('global_completeness_gate_failed_')
  expect(qs).toMatch(/storage\.from\(["']evidence["']\)\.upload/)
  expect(qs).toContain('svc_ranking_raw_evidence_register')

  expect(the).toMatch(/if\s*\(\s*u\.protocol\s*!==\s*["']https:["']\s*\|\|\s*u\.hostname\s*!==\s*["']www\.timeshighereducation\.com["']\s*\)\s*throw/)
  expect(the).toMatch(/world-university-rankings/)
  expect(the).toContain('the_completeness_gate_failed_')
  expect(the).toContain('publisher_total')
  expect(the).toMatch(/storage\.from\(["']evidence["']\)\.upload/)
  expect(the).toContain('svc_ranking_raw_evidence_register')
})

test('ranking ingest remains service-role-only and evidence export stays short-lived', async () => {
  const [migration, allMigrations, exportWorker] = await Promise.all([
    read('supabase/migrations/20260905085600_cf_213_ranking_indicator_rank_semantics.sql'),
    readAllMigrations(),
    read('supabase/functions/ranking-evidence-export/index.ts'),
  ])

  expect(migration).toContain('revoke all on function public.svc_ranking_ingest_apply')
  expect(migration).toContain('grant execute on function public.svc_ranking_ingest_apply')
  expect(migration).toContain('to service_role')
  expect(effectiveIngestExecuteGrantees(allMigrations)).toEqual(['service_role'])
  expect(exportWorker).toMatch(/createSignedUrl\(\s*[^,]+,\s*300\s*(?:,|\))/)
  expect(exportWorker).toContain('authorised_role_required')
})

test('evidence lineage remains non-destructive and excludes logical URI schemes from storage checks', async () => {
  const migration = await read('supabase/migrations/20260901195000_m2_5_evidence_lineage_classification.sql')

  expect(migration).toContain("e.storage_path !~ '^[A-Za-z][A-Za-z0-9+.-]*://'")
  expect(migration).toContain("'unlinked_storage_object_count_raw'")
  expect(migration).toContain("'virtual_evidence_reference_count'")
  expect(migration).not.toMatch(/delete\s+from\s+(pipeline\.evidence_artifacts|storage\.objects)/i)
})

test('historical lineage reconciliation and provider-contact claiming remain concurrency-safe', async () => {
  const migration = await read('supabase/migrations/20260901224000_m2_5_evidence_lineage_reconciliation_contact_claim.sql')

  expect(migration).toContain('create table if not exists pipeline.evidence_lineage_reconciliations')
  expect(migration).toContain('add column if not exists claim_token uuid')
  expect(migration).toContain('add column if not exists claim_until timestamptz')
  expect(migration).toContain('for update of pcp skip locked')
  expect(migration).toContain('stale or invalid Provider-contact claim token')
  expect(migration).not.toMatch(/delete\s+from\s+(?:pipeline\.evidence_artifacts|storage\.objects)/i)
  expect(migration).not.toMatch(/update\s+pipeline\.evidence_artifacts/i)
})

test('platform administration contract remains operator-gated, non-destructive and secret references stay server-side', async () => {
  const allMigrations = await readAllMigrations()
  const effective = latestFunctionDefinition(allMigrations, 'security.admin_platform_maturity_read')

  expect(effective).toMatch(/create\s+(?:or\s+replace\s+)?function\s+(?:"security"|security)\s*\.\s*(?:"admin_platform_maturity_read"|admin_platform_maturity_read)/i)
  expect(effective).toMatch(/if\s+v_rank\s*<\s*4\s+then\s+raise\s+exception\s+["']pipeline_operator role required["']/i)
  expect(effective).not.toContain('vault_secret_id')
  expect(effective).not.toContain('secret_env_key')
  expect(effective).not.toMatch(/\bdelete\s+from\b/i)
  expect(effective).not.toMatch(/\btruncate\s+(?:table\s+)?(?:only\s+)?pipeline\.(?:environment_source_gates|layer2_provider_environment_gates|layer3_profile_environment_gates)\b/i)
  expect(effective).not.toMatch(/\bupdate\s+pipeline\.(?:environment_source_gates|layer2_provider_environment_gates|layer3_profile_environment_gates)\b/i)
})

test('browser Supabase boundary remains centralised, publishable-key only and public.admin_read only', async () => {
  const files = await readSourceFiles()
  const client = files.find(file => file.path === 'src/lib/supabase.ts')
  expect(client).toBeTruthy()

  const combined = files.map(file => `\n-- ${file.path}\n${file.content}`).join('\n')
  expect(combined).not.toMatch(/service[_-]?role/i)
  expect(combined).not.toMatch(/SUPABASE_SERVICE/i)

  const clientCreators = files.filter(file => /\bcreateClient\s*\(/.test(stripCodeComments(file.content)))
  expect(clientCreators.map(file => file.path)).toEqual(['src/lib/supabase.ts'])

  expect(client.content).toContain('VITE_SUPABASE_URL')
  expect(client.content).toContain('VITE_SUPABASE_PUBLISHABLE_KEY')
  expect(client.content).toContain("supabase.rpc('admin_read'")
})
