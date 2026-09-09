import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'

const read = filePath => fs.readFile(filePath, 'utf8')

async function readAllMigrations() {
  const dir = 'supabase/migrations'
  const names = (await fs.readdir(dir)).filter(name => name.endsWith('.sql')).sort()
  const chunks = []
  for (const name of names) chunks.push(await read(`${dir}/${name}`))
  return chunks.join('\n')
}

function splitSqlStatements(source) {
  const statements = []
  let current = ''
  let i = 0
  let single = false
  let double = false
  let dollarTag = null
  let lineComment = false
  let blockComment = false

  const flush = () => {
    const value = current.trim()
    if (value) statements.push(value)
    current = ''
  }

  while (i < source.length) {
    const ch = source[i]
    const next = source[i + 1]

    if (lineComment) {
      if (ch === '\n') {
        lineComment = false
        current += '\n'
      } else current += ' '
      i += 1
      continue
    }

    if (blockComment) {
      if (ch === '*' && next === '/') {
        current += '  '
        i += 2
        blockComment = false
      } else {
        current += ch === '\n' ? '\n' : ' '
        i += 1
      }
      continue
    }

    if (dollarTag) {
      if (source.startsWith(dollarTag, i)) {
        current += dollarTag
        i += dollarTag.length
        dollarTag = null
      } else {
        current += ch
        i += 1
      }
      continue
    }

    if (single) {
      current += ch
      if (ch === "'" && next === "'") {
        current += next
        i += 2
      } else {
        if (ch === "'") single = false
        i += 1
      }
      continue
    }

    if (double) {
      current += ch
      if (ch === '"' && next === '"') {
        current += next
        i += 2
      } else {
        if (ch === '"') double = false
        i += 1
      }
      continue
    }

    if (ch === '-' && next === '-') {
      current += '  '
      i += 2
      lineComment = true
      continue
    }
    if (ch === '/' && next === '*') {
      current += '  '
      i += 2
      blockComment = true
      continue
    }
    if (ch === "'") {
      single = true
      current += ch
      i += 1
      continue
    }
    if (ch === '"') {
      double = true
      current += ch
      i += 1
      continue
    }

    const dollar = source.slice(i).match(/^\$[A-Za-z_][A-Za-z0-9_]*\$|^\$\$/)
    if (dollar) {
      dollarTag = dollar[0]
      current += dollarTag
      i += dollarTag.length
      continue
    }

    if (ch === ';') {
      flush()
      i += 1
      continue
    }

    current += ch
    i += 1
  }

  flush()
  return statements
}

function executableSql(source) {
  let out = ''
  let i = 0
  let single = false
  let double = false
  let lineComment = false
  let blockComment = false

  while (i < source.length) {
    const ch = source[i]
    const next = source[i + 1]

    if (lineComment) {
      if (ch === '\n') {
        lineComment = false
        out += '\n'
      } else out += ' '
      i += 1
      continue
    }
    if (blockComment) {
      if (ch === '*' && next === '/') {
        out += '  '
        i += 2
        blockComment = false
      } else {
        out += ch === '\n' ? '\n' : ' '
        i += 1
      }
      continue
    }
    if (single) {
      if (ch === "'" && next === "'") {
        out += '  '
        i += 2
      } else {
        out += ch === '\n' ? '\n' : ' '
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
      out += '  '
      i += 2
      lineComment = true
      continue
    }
    if (ch === '/' && next === '*') {
      out += '  '
      i += 2
      blockComment = true
      continue
    }
    if (ch === "'") {
      single = true
      out += ' '
      i += 1
      continue
    }
    if (ch === '"') {
      double = true
      out += ch
      i += 1
      continue
    }
    out += ch
    i += 1
  }
  return out
}

function topLevelSql(source) {
  const statements = splitSqlStatements(source)
  return statements.map(statement => {
    let out = ''
    let i = 0
    let single = false
    let double = false
    let dollarTag = null
    while (i < statement.length) {
      const ch = statement[i]
      const next = statement[i + 1]
      if (dollarTag) {
        if (statement.startsWith(dollarTag, i)) {
          out += ' '.repeat(dollarTag.length)
          i += dollarTag.length
          dollarTag = null
        } else {
          out += ch === '\n' ? '\n' : ' '
          i += 1
        }
        continue
      }
      if (single) {
        if (ch === "'" && next === "'") {
          out += '  '
          i += 2
        } else {
          out += ch === '\n' ? '\n' : ' '
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
      if (ch === "'") {
        single = true
        out += ' '
        i += 1
        continue
      }
      if (ch === '"') {
        double = true
        out += ch
        i += 1
        continue
      }
      const dollar = statement.slice(i).match(/^\$[A-Za-z_][A-Za-z0-9_]*\$|^\$\$/)
      if (dollar) {
        dollarTag = dollar[0]
        out += ' '.repeat(dollarTag.length)
        i += dollarTag.length
        continue
      }
      out += ch
      i += 1
    }
    return { raw: statement, top: out }
  })
}

function canonicalType(type) {
  return type
    .replace(/\bpg_catalog\s*\.\s*/gi, '')
    .replace(/\bint2\b/gi, 'smallint')
    .replace(/\bint4\b/gi, 'integer')
    .replace(/\bint8\b/gi, 'bigint')
    .replace(/\bfloat4\b/gi, 'real')
    .replace(/\bfloat8\b/gi, 'double precision')
    .replace(/\bbool\b/gi, 'boolean')
    .replace(/\bvarchar\b/gi, 'character varying')
    .replace(/\btimestamptz\b/gi, 'timestamp with time zone')
    .replace(/\btimetz\b/gi, 'time with time zone')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase()
}

function splitTopLevelComma(raw) {
  const parts = []
  let current = ''
  let depth = 0
  for (const ch of raw) {
    if (ch === '(' || ch === '[') depth += 1
    if (ch === ')' || ch === ']') depth -= 1
    if (ch === ',' && depth === 0) {
      parts.push(current.trim())
      current = ''
    } else current += ch
  }
  if (current.trim()) parts.push(current.trim())
  return parts
}

function canonicalSignature(raw) {
  if (!raw.trim()) return ''
  return splitTopLevelComma(raw)
    .map(argument => canonicalType(argument
      .replace(/\bdefault\b[\s\S]*$/i, '')
      .replace(/=[\s\S]*$/i, '')
      .replace(/^(?:(?:in|out|inout|variadic)\s+)?"?[A-Za-z_][A-Za-z0-9_]*"?\s+/i, '')
      .replace(/"/g, '')
      .trim()))
    .join(',')
}

function cleanIdentifier(raw) {
  return raw.trim().replace(/^"|"$/g, '').toLowerCase()
}

function parseSearchPath(statement, current) {
  const match = statement.match(/^\s*set\s+(?:local\s+)?search_path\s+(?:to|=)\s+(.+)$/i)
  if (!match) return current
  return splitTopLevelComma(match[1])
    .map(part => cleanIdentifier(part))
    .filter(part => part && part !== '$user')
}

function qualifyName(rawName, searchPath) {
  const parts = rawName.split('.').map(cleanIdentifier)
  if (parts.length === 2) return `${parts[0]}.${parts[1]}`
  return `${searchPath.find(schema => schema !== 'pg_catalog') || 'public'}.${parts[0]}`
}

function parseRoutineTarget(raw, searchPath) {
  const match = raw.trim().match(/^((?:"?[A-Za-z_][A-Za-z0-9_]*"?\s*\.\s*)?"?[A-Za-z_][A-Za-z0-9_]*"?)\s*\(([\s\S]*)\)$/)
  if (!match) return null
  return { name: qualifyName(match[1].replace(/\s+/g, ''), searchPath), signature: canonicalSignature(match[2]) }
}

function parseRoles(raw) {
  return splitTopLevelComma(raw)
    .map(role => role.replace(/\bwith\s+grant\s+option\b/gi, '').trim())
    .map(cleanIdentifier)
    .filter(Boolean)
}

function routineState(rawSql) {
  const statements = topLevelSql(rawSql)
  const definitions = new Map()
  const acl = new Map()
  const defaultAcl = new Map()
  let searchPath = ['public']

  const defaultFor = schema => {
    if (!defaultAcl.has(schema)) defaultAcl.set(schema, new Set(['public']))
    return defaultAcl.get(schema)
  }

  for (const { raw, top } of statements) {
    searchPath = parseSearchPath(top, searchPath)

    const defaultMatch = top.match(/^\s*alter\s+default\s+privileges(?:[\s\S]*?in\s+schema\s+([^\s]+))?[\s\S]*?\b(grant|revoke)\s+(?:execute|all(?:\s+privileges)?)\s+on\s+(?:functions|routines)\s+(?:to|from)\s+([\s\S]+)$/i)
    if (defaultMatch) {
      const schema = defaultMatch[1] ? cleanIdentifier(defaultMatch[1]) : (searchPath.find(x => x !== 'pg_catalog') || 'public')
      const roles = parseRoles(defaultMatch[3])
      for (const role of roles) {
        if (defaultMatch[2].toLowerCase() === 'grant') defaultFor(schema).add(role)
        else defaultFor(schema).delete(role)
      }
      continue
    }

    const create = top.match(/^\s*create\s+(or\s+replace\s+)?function\s+((?:"?[A-Za-z_][A-Za-z0-9_]*"?\s*\.\s*)?"?[A-Za-z_][A-Za-z0-9_]*"?)\s*\(([^)]*)\)/i)
    if (create) {
      const name = qualifyName(create[2].replace(/\s+/g, ''), searchPath)
      const signature = canonicalSignature(create[3])
      const key = `${name}(${signature})`
      definitions.set(key, raw)
      if (!create[1] || !acl.has(key)) {
        const schema = name.split('.')[0]
        acl.set(key, new Set(defaultFor(schema)))
      }
      continue
    }

    const drop = top.match(/^\s*drop\s+(?:function|routine)\s+(?:if\s+exists\s+)?((?:"?[A-Za-z_][A-Za-z0-9_]*"?\s*\.\s*)?"?[A-Za-z_][A-Za-z0-9_]*"?)\s*\(([^)]*)\)/i)
    if (drop) {
      const name = qualifyName(drop[1].replace(/\s+/g, ''), searchPath)
      const key = `${name}(${canonicalSignature(drop[2])})`
      definitions.delete(key)
      acl.delete(key)
      continue
    }

    const alter = top.match(/^\s*alter\s+(?:function|routine)\s+((?:"?[A-Za-z_][A-Za-z0-9_]*"?\s*\.\s*)?"?[A-Za-z_][A-Za-z0-9_]*"?)\s*\(([^)]*)\)\s+(rename\s+to|set\s+schema)\b/i)
    if (alter) {
      const name = qualifyName(alter[1].replace(/\s+/g, ''), searchPath)
      const key = `${name}(${canonicalSignature(alter[2])})`
      definitions.delete(key)
      acl.delete(key)
      continue
    }

    const schemaAcl = top.match(/^\s*(grant|revoke)\s+(?:execute|all(?:\s+privileges)?)\s+on\s+all\s+(?:functions|routines)\s+in\s+schema\s+([^\s]+)\s+(?:to|from)\s+([\s\S]+)$/i)
    if (schemaAcl) {
      const schema = cleanIdentifier(schemaAcl[2])
      const roles = parseRoles(schemaAcl[3])
      for (const [key, rolesForRoutine] of acl) {
        if (!key.startsWith(`${schema}.`)) continue
        for (const role of roles) {
          if (schemaAcl[1].toLowerCase() === 'grant') rolesForRoutine.add(role)
          else rolesForRoutine.delete(role)
        }
      }
      continue
    }

    const functionAcl = top.match(/^\s*(grant|revoke)\s+(?:execute|all(?:\s+privileges)?)\s+on\s+(?:function|routine)\s+([\s\S]+?)\s+(to|from)\s+([\s\S]+)$/i)
    if (functionAcl) {
      const targets = splitTopLevelComma(functionAcl[2])
      const roles = parseRoles(functionAcl[4])
      for (const targetRaw of targets) {
        const target = parseRoutineTarget(targetRaw, searchPath)
        if (!target) continue
        const key = `${target.name}(${target.signature})`
        const rolesForRoutine = acl.get(key)
        if (!rolesForRoutine) continue
        for (const role of roles) {
          if (functionAcl[1].toLowerCase() === 'grant') rolesForRoutine.add(role)
          else rolesForRoutine.delete(role)
        }
      }
    }
  }

  return { definitions, acl }
}

function expectServiceRoleOnly(state, key) {
  expect(state.definitions.has(key), `${key} must exist`).toBe(true)
  expect([...(state.acl.get(key) || [])].sort(), `${key} must be service-role-only`).toEqual(['service_role'])
}

test('effective governed routine state is signature-specific and privilege-safe', async () => {
  const migrations = await readAllMigrations()
  const state = routineState(migrations)

  const ingest = [...state.acl.entries()].filter(([key]) => key.startsWith('public.svc_ranking_ingest_apply('))
  expect(ingest.length).toBeGreaterThan(0)
  for (const [key, roles] of ingest) expect([...roles].sort(), key).toEqual(['service_role'])

  expectServiceRoleOnly(state, 'public.provider_contact_profiles_claim_service(uuid,integer,integer)')
  expectServiceRoleOnly(state, 'public.provider_contact_profile_finish_claim_service(uuid,uuid,text,text)')

  const platformKey = 'security.admin_platform_maturity_read(text,jsonb)'
  expect(state.definitions.has(platformKey), `${platformKey} must exist with its routed signature`).toBe(true)
  const platformBody = executableSql(state.definitions.get(platformKey) || '')
  expect(platformBody).toMatch(/if\s+v_rank\s*<\s*4\s+then\s+raise\s+exception/i)
})

test('effective non-destructive routines reject destructive evidence operations', async () => {
  const migrations = await readAllMigrations()
  const state = routineState(migrations)
  const keys = [
    'security.platform_capacity_snapshot_internal(text)',
    'public.provider_contact_profiles_claim_service(uuid,integer,integer)',
    'public.provider_contact_profile_finish_claim_service(uuid,uuid,text,text)',
  ]

  for (const key of keys) {
    expect(state.definitions.has(key), `${key} must exist`).toBe(true)
    const body = executableSql(state.definitions.get(key) || '')
    expect(body, `${key} must not DELETE governed evidence`).not.toMatch(/\bdelete\s+from\s+(?:pipeline\s*\.\s*evidence_artifacts|storage\s*\.\s*objects)\b/i)
    expect(body, `${key} must not TRUNCATE governed evidence`).not.toMatch(/\btruncate\s+(?:table\s+)?(?:only\s+)?(?:pipeline\s*\.\s*evidence_artifacts|storage\s*\.\s*objects)\b/i)
    expect(body, `${key} must not UPDATE governed evidence`).not.toMatch(/\bupdate\s+(?:pipeline\s*\.\s*evidence_artifacts|storage\s*\.\s*objects)\b/i)
  }
})

test('SQL parser closes EOF, literal, overload, default-privilege and multi-target bypass classes', () => {
  const synthetic = `
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated;
    CREATE FUNCTION public.svc_ranking_ingest_apply(p_value int4) RETURNS void LANGUAGE sql AS $$ SELECT 1 $$;
    REVOKE EXECUTE ON FUNCTION public.svc_ranking_ingest_apply(integer) FROM public;
    GRANT EXECUTE ON FUNCTION public.other(), public.svc_ranking_ingest_apply(integer) TO service_role;
    SELECT 'GRANT EXECUTE ON FUNCTION public.svc_ranking_ingest_apply(integer) TO service_role';
    GRANT EXECUTE ON ROUTINE public.svc_ranking_ingest_apply(integer) TO authenticated`
  const state = routineState(synthetic)
  expect([...(state.acl.get('public.svc_ranking_ingest_apply(integer)') || [])].sort()).toEqual(['authenticated', 'service_role'])

  const signatureSynthetic = `
    CREATE FUNCTION security.admin_platform_maturity_read(p_operation text, p_args jsonb) RETURNS void LANGUAGE sql AS $$ SELECT 1 $$;
    CREATE FUNCTION security.admin_platform_maturity_read(p_operation text) RETURNS void LANGUAGE sql AS $$ SELECT 2 $$;
    SELECT 'CREATE FUNCTION security.admin_platform_maturity_read(text,jsonb)';`
  const signatureState = routineState(signatureSynthetic)
  expect(signatureState.definitions.has('security.admin_platform_maturity_read(text,jsonb)')).toBe(true)
  expect(signatureState.definitions.has('security.admin_platform_maturity_read(text)')).toBe(true)
})

test('unqualified search-path DDL and ALTER removal affect governed target state', () => {
  const synthetic = `
    SET search_path TO security, public;
    CREATE FUNCTION admin_platform_maturity_read(p_operation text, p_args jsonb) RETURNS void LANGUAGE sql AS $$ SELECT 1 $$;
    ALTER FUNCTION admin_platform_maturity_read(text,jsonb) RENAME TO retired_admin_platform_maturity_read;`
  const state = routineState(synthetic)
  expect(state.definitions.has('security.admin_platform_maturity_read(text,jsonb)')).toBe(false)
})
