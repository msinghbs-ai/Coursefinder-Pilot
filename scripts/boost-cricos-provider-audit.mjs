// S3-Boost providers, s700. One publisher edition and one read-only Management API query.
import { createHash } from 'node:crypto'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import { CsvParser } from './export/csv.mjs'
import { lit, need, read } from './boost-live-lib.mjs'
import { normaliseCricosProviderWebsite } from '../supabase/functions/_shared/cf247-cricos-provider-website.mjs'

const EDITION_SHA = 'd62824262a8184ebb16a9caa13d7dc5d438fbce348556febf6a37e2b9481a11f'
const tidy = value => String(value ?? '').trim()
const normaliseName = value => tidy(value).replace(/\s+/gu, ' ').toLowerCase()
const nameParts = value => tidy(value).split(/[;,]/u).map(tidy).filter(Boolean)
const domain = url => url ? new URL(url).hostname.toLowerCase().replace(/^www\./u, '').replace(/\.$/u, '') : null

function parseSource(bytes) {
  const header = ['CRICOS Provider Code', 'Institution Name', 'Trading Name', 'Website']
  let indices
  const rows = []
  const codes = new Set()
  const parser = new CsvParser(cells => {
    if (!indices) {
      indices = header.map(name => cells.findIndex(cell => tidy(cell).replace(/^\uFEFF/u, '') === name))
      if (indices.some(index => index < 0)) throw Error('Required CRICOS Institutions headers missing')
      return
    }
    if (!cells.some(tidy)) return
    const [code, legal, trading, website] = indices.map(index => tidy(cells[index]))
    if (!/^\d{5}[A-Z]$/u.test(code) || !legal || codes.has(code)) throw Error('Invalid or duplicate CRICOS Institutions row: ' + code)
    codes.add(code)
    rows.push({ code, legal, trading, website })
  })
  parser.push(bytes)
  parser.end()
  if (!rows.length) throw Error('The CRICOS Institutions export contains no providers')
  return rows.sort((a, b) => a.code.localeCompare(b.code, 'en-AU'))
}

function sourceNames(row) {
  return [
    ['code', row.code], ['legal', row.legal], ['trading', row.trading],
    ...nameParts(row.trading).map(name => ['trading', name]),
  ].filter(([, name]) => tidy(name)).map(([kind, name]) => ({ kind, name: normaliseName(name) }))
}

function grouped(rows) {
  const index = new Map()
  for (const row of rows) {
    if (!index.has(row.code)) index.set(row.code, [])
    index.get(row.code).push(row)
  }
  return index
}

export function reconcileProviders(source, exactRows, aliasRows) {
  const exact = grouped(exactRows)
  const aliases = grouped(aliasRows)
  const telemetry = {
    source: 'CRICOS_PROVIDERS_PILOT', sample_size: source.length, matched_exact: 0, alias_candidates_found: 0,
    domain_mismatch_count: 0, missing_url_count: 0, bare_scheme_urls_normalised: 0,
    execution_duration_ms: 0, llm_cost_usd: 0.00,
  }
  const result = {
    telemetry, matched_active: 0, source_missing_urls: [], source_invalid_urls: [], source_missing_trading_names: [],
    domain_mismatches: [], alias_candidates: [], alias_only_codes: [], cross_provider_alias_codes: [],
    missing_catalogue_urls: [], invalid_catalogue_urls: [], uncovered_trading_names: [],
    unmatched_codes: [], duplicate_exact_codes: [], inactive_exact_codes: [],
  }
  for (const row of source) {
    const matches = exact.get(row.code) || []
    const candidateAliases = aliases.get(row.code) || []
    const providerIds = new Set(matches.map(match => match.id))
    const active = matches.find(value => value.registration_status === 'active' && value.lifecycle_status === 'active')
    const match = active || matches[0]
    const sourceUrl = normaliseCricosProviderWebsite(row.website)
    if (!tidy(row.website)) result.source_missing_urls.push(row.code)
    else if (!sourceUrl) result.source_invalid_urls.push({ code: row.code, website: row.website })
    else if (sourceUrl !== tidy(row.website)) telemetry.bare_scheme_urls_normalised++
    if (!tidy(row.trading)) result.source_missing_trading_names.push(row.code)

    if (candidateAliases.length) {
      telemetry.alias_candidates_found++
      if (!match) result.alias_only_codes.push(row.code)
      else if (candidateAliases.some(alias => !providerIds.has(alias.provider_id))) result.cross_provider_alias_codes.push(row.code)
      for (const { provider_id: candidateId, ...alias } of candidateAliases) {
        result.alias_candidates.push({ ...alias, same_provider: providerIds.has(candidateId) })
      }
    }
    if (!match) {
      result.unmatched_codes.push({ code: row.code, legal: row.legal, trading: row.trading })
      continue
    }
    telemetry.matched_exact++
    if (active) result.matched_active++
    else result.inactive_exact_codes.push({ code: row.code, registration_status: match.registration_status, lifecycle_status: match.lifecycle_status })
    if (providerIds.size > 1) {
      result.duplicate_exact_codes.push(row.code)
      continue
    }

    const sourceDomain = domain(sourceUrl)
    const catalogueDomain = domain(normaliseCricosProviderWebsite(match.website))
    const provider = match.display_name || match.canonical_name
    if (!tidy(match.website)) result.missing_catalogue_urls.push({ code: row.code, provider, source_website: row.website })
    else if (!catalogueDomain) result.invalid_catalogue_urls.push({ code: row.code, website: match.website })
    if (sourceDomain && catalogueDomain && sourceDomain !== catalogueDomain) {
      result.domain_mismatches.push({ code: row.code, provider, source_website: row.website, catalogue_website: match.website })
    }
    const names = new Set([match.display_name, match.canonical_name, match.short_name, ...candidateAliases.filter(alias => alias.provider_id === match.id).map(alias => alias.alias)].map(normaliseName).filter(Boolean))
    if (row.trading && !names.has(normaliseName(row.trading))) {
      const uncovered = [...new Set(nameParts(row.trading))].filter(name => !names.has(normaliseName(name)))
      if (uncovered.length) result.uncovered_trading_names.push({ code: row.code, names: uncovered })
    }
  }
  telemetry.domain_mismatch_count = result.domain_mismatches.length
  telemetry.missing_url_count = result.missing_catalogue_urls.length
  return result
}

function auditSql(source) {
  const inputs = lit(JSON.stringify(source.map(row => ({ code: row.code, names: sourceNames(row) }))))
  return [
    'WITH sample AS MATERIALIZED (',
    '  SELECT * FROM jsonb_to_recordset(' + inputs + '::jsonb) AS s(code text, names jsonb)',
    '), exact AS (',
    "  SELECT s.code, p.id, r.status AS registration_status, p.lifecycle_status, p.website, p.canonical_name, p.display_name, p.short_name",
    "  FROM sample s JOIN catalogue.provider_registrations r ON r.registration_scheme = 'cricos' AND upper(btrim(r.registration_code)) = s.code",
    "  JOIN catalogue.providers p ON p.id = r.provider_id JOIN ref.countries c ON c.id = p.country_id AND c.iso_alpha2 = 'AU'",
    '), aliases AS (',
    '  SELECT DISTINCT s.code, a.provider_id, a.alias, a.alias_type, n.kind, coalesce(p.display_name, p.canonical_name) AS candidate_provider',
    '  FROM sample s CROSS JOIN LATERAL jsonb_to_recordset(s.names) AS n(kind text, name text)',
    "  JOIN catalogue.provider_aliases a ON lower(regexp_replace(btrim(a.alias), '[[:space:]]+', ' ', 'g')) = n.name",
    "  JOIN catalogue.providers p ON p.id = a.provider_id AND p.lifecycle_status = 'active'",
    "  JOIN ref.countries c ON c.id = p.country_id AND c.iso_alpha2 = 'AU'",
    '  WHERE (a.valid_from IS NULL OR a.valid_from <= current_date) AND (a.valid_to IS NULL OR a.valid_to >= current_date)',
    '), live_functions AS MATERIALIZED (',
    "  SELECT p.oid, n.nspname || '.' || p.proname AS name, md5(pg_catalog.pg_get_functiondef(p.oid)) AS md5",
    '  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace',
    "  WHERE (n.nspname = 'public' AND p.proname ~ '^(website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1$)') OR n.nspname = 'api'",
    '), g3_drift AS (',
    '  SELECT coalesce(b.name, f.name) AS name FROM live_functions f FULL JOIN',
    "    (SELECT b.name, b.md5 FROM pipeline.consumer_api_baseline b WHERE b.kind = 'function') b ON pg_catalog.to_regprocedure(b.name) = f.oid",
    '  WHERE f.md5 IS DISTINCT FROM b.md5',
    '  UNION ALL',
    "  SELECT b.name FROM pipeline.consumer_api_baseline b CROSS JOIN LATERAL jsonb_each_text(b.columns) k",
    '  LEFT JOIN pg_catalog.pg_attribute a ON a.attrelid = to_regclass(b.name) AND a.attname = k.key AND a.attnum > 0 AND NOT a.attisdropped',
    "  WHERE b.kind = 'relation' AND pg_catalog.format_type(a.atttypid, a.atttypmod) IS DISTINCT FROM k.value",
    ') SELECT',
    "  coalesce((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.code, e.id) FROM exact e), '[]'::jsonb) AS exact,",
    "  coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.code, a.alias, a.kind, a.provider_id) FROM aliases a), '[]'::jsonb) AS aliases,",
    "  (SELECT count(*) FROM live_functions) AS functions,",
    "  (SELECT count(*) FROM pipeline.consumer_api_baseline WHERE kind = 'relation') AS relations,",
    "  coalesce((SELECT jsonb_agg(name ORDER BY name) FROM g3_drift), '[]'::jsonb) AS drift,",
    '  (SELECT max(version) FROM supabase_migrations.schema_migrations) AS migration_head',
  ].join('\n')
}

async function main() {
  need()
  const input = process.argv[2]
  const output = process.argv[3]
  if (!input || !output) throw Error('Usage: node scripts/boost-cricos-provider-audit.mjs institutions.csv output-directory')
  const start = performance.now()
  const bytes = await readFile(input)
  const sha = createHash('sha256').update(bytes).digest('hex')
  if (sha !== EDITION_SHA) throw Error('The export does not match the approved 2 November 2026 Institutions file SHA-256')
  const source = parseSource(bytes)
  const [data] = await read(auditSql(source))
  if (!data || Number(data.functions) !== 75 || Number(data.relations) !== 48 || !Array.isArray(data.drift) || data.drift.length) {
    throw Error('G3 live baseline mismatch: ' + JSON.stringify({ functions: data?.functions, relations: data?.relations, drift: data?.drift }))
  }
  const result = reconcileProviders(source, data.exact, data.aliases)
  result.telemetry.execution_duration_ms = Math.round(performance.now() - start)
  result.edition = '2026-11-02'
  result.source_sha256 = sha
  result.p_write = false
  result.g3 = { functions: Number(data.functions), tables: Number(data.relations), drift: data.drift }
  result.migration_head = data.migration_head
  await mkdir(output, { recursive: true })
  const json = JSON.stringify(result, null, 2).replace('"llm_cost_usd": 0\n', '"llm_cost_usd": 0.00\n')
  await writeFile(resolve(output, 'cricos-provider-audit.json'), json + '\n')
  console.log('CRICOS_TELEMETRY ' + JSON.stringify(result.telemetry))
  for (const [key, value] of Object.entries(result)) {
    if (Array.isArray(value)) for (const row of value) console.log('CRICOS_DETAIL ' + JSON.stringify([key, row]))
    else if (key !== 'telemetry') console.log('CRICOS_DETAIL ' + JSON.stringify([key, value]))
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) await main()
