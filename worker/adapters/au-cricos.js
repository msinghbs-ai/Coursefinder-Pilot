import { unzipSync, strFromU8 } from 'fflate'
import { parseCsv, normaliseRow, pick, cleanCode, numericText } from '../lib/csv'
import { rpc } from '../lib/service'

export async function runAuCricos({ client, source, jobId, apply, maxRecords, version }) {
  const discoveryUrl = source?.source_metadata?.discovery_url
  if (!discoveryUrl) throw new Error('CRICOS discovery_url is not configured in Regulatory Settings')

  const metaResp = await fetch(discoveryUrl, { headers: { 'user-agent': 'Coursefinder-Layer1/0.1' } })
  if (!metaResp.ok) throw new Error(`CRICOS metadata failed: ${metaResp.status}`)
  const meta = await metaResp.json()
  if (!meta.success || !meta.result) throw new Error('CRICOS package metadata invalid')

  const resource = chooseLatestZip(meta.result.resources || [])
  if (!resource) throw new Error('No CRICOS ZIP resource found')

  const response = await fetch(resource.url, { headers: { 'user-agent': 'Coursefinder-Layer1/0.1' } })
  if (!response.ok) throw new Error(`CRICOS download failed: ${response.status}`)
  const bytes = new Uint8Array(await response.arrayBuffer())
  const hash = await sha256Hex(bytes)
  const resourceDate = resource.last_modified || resource.created || new Date().toISOString()
  const storagePath = `regulatory/AU/cricos/${resourceDate.slice(0, 10)}/${hash}.zip`

  const { error: uploadError } = await client.storage.from('evidence').upload(storagePath, bytes, {
    contentType: 'application/zip', upsert: true, cacheControl: '3600',
  })
  if (uploadError) throw new Error(`Evidence upload failed: ${uploadError.message}`)

  const evidenceId = await rpc(client, 'svc_layer1_record_evidence', {
    p_source_id: source.source_id,
    p_job_id: jobId,
    p_source_url: resource.url,
    p_storage_path: storagePath,
    p_content_hash: hash,
    p_mime_type: 'application/zip',
    p_metadata: {
      dataset: 'CRICOS', discovery_url: discoveryUrl, resource_id: resource.id, resource_name: resource.name,
      resource_updated: resource.last_modified || resource.created || null,
      package_modified: meta.result.metadata_modified || null, byte_size: bytes.byteLength,
    },
  })

  const records = extractRecords(bytes)
  const selected = maxRecords > 0 ? records.slice(0, maxRecords) : records
  const reconciliation = apply ? await applyBatches(client, source.source_id, evidenceId, selected) : drySummary(selected.length)

  return {
    adapter: 'au_cricos', workerVersion: version, mode: apply ? 'apply' : 'dry-run',
    resource: { id: resource.id, name: resource.name, url: resource.url, updated: resourceDate },
    evidenceId, storagePath, contentHash: hash, parsedRecords: records.length, selectedRecords: selected.length,
    reconciliation,
    sourceHealth: { content_hash: hash, resource_id: resource.id, resource_updated: resourceDate, parsed_records: records.length },
  }
}

async function applyBatches(client, sourceId, evidenceId, records) {
  const total = drySummary(0)
  for (let i = 0; i < records.length; i += 250) {
    const batch = records.slice(i, i + 250)
    const result = await rpc(client, 'svc_layer1_apply_cricos_records', {
      p_source_id: sourceId, p_evidence_id: evidenceId, p_records: batch,
    })
    for (const key of Object.keys(total)) total[key] += Number(result?.[key] || 0)
  }
  return total
}

function drySummary(records) {
  return { provider_created: 0, provider_linked: 0, course_created: 0, course_linked: 0, conflicts: 0, records }
}

function chooseLatestZip(resources) {
  return resources
    .filter(r => String(r.format || '').toUpperCase() === 'ZIP' && r.url && /cricos/i.test(`${r.name || ''} ${r.url}`))
    .sort((a, b) => resourceTime(b) - resourceTime(a))[0] || null
}
function resourceTime(r) { const n = Date.parse(r.last_modified || r.created || r.metadata_modified || ''); return Number.isFinite(n) ? n : 0 }

function extractRecords(zipBytes) {
  const archive = unzipSync(zipBytes)
  const csvs = Object.entries(archive)
    .filter(([name]) => name.toLowerCase().endsWith('.csv'))
    .map(([name, data]) => ({ name, rows: parseCsv(strFromU8(data)) }))
  if (!csvs.length) throw new Error('CRICOS ZIP contained no CSV files')

  const providers = new Map()
  for (const file of csvs) for (const raw of file.rows) {
    const row = normaliseRow(raw)
    const code = pick(row, ['provider code', 'cricos provider code', 'provider cricos code', 'institution code'])
    const name = pick(row, ['provider name', 'institution name', 'provider trading name', 'institution trading name'])
    if (code && name) providers.set(cleanCode(code), name.trim())
  }

  const out = [], seen = new Set()
  for (const file of csvs) for (const raw of file.rows) {
    const row = normaliseRow(raw)
    const courseCode = pick(row, ['course code', 'cricos course code'])
    const courseName = pick(row, ['course name', 'course title'])
    const providerCodeRaw = pick(row, ['provider code', 'cricos provider code', 'provider cricos code', 'institution code'])
    if (!courseCode || !courseName || !providerCodeRaw) continue
    const courseKey = cleanCode(courseCode), providerCode = cleanCode(providerCodeRaw)
    if (seen.has(courseKey)) continue
    const providerName = pick(row, ['provider name', 'institution name', 'provider trading name', 'institution trading name']) || providers.get(providerCode)
    if (!providerName) continue
    seen.add(courseKey)
    out.push({
      provider_code: providerCode,
      provider_name: providerName.trim(),
      course_code: courseKey,
      course_name: courseName.trim(),
      course_level: pick(row, ['course level', 'qualification type', 'course type']) || null,
      duration_weeks: numericText(pick(row, ['duration weeks', 'duration (weeks)', 'course duration weeks', 'duration'])) || null,
    })
  }
  if (!out.length) throw new Error(`CRICOS parsing produced zero course records; CSV files: ${csvs.map(x => x.name).join(', ')}`)
  return out
}

async function sha256Hex(bytes) {
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('')
}
