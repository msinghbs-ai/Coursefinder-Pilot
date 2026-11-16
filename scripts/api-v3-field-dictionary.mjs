#!/usr/bin/env node
// Guards: REQ-76 API v3 field dictionary (Platform Admin 15 Nov 2026, combined build item 1).
// docs/api/v3/field-dictionary.json is the reviewed list of every Website API v3 and Zoho API v3 field. This script checks it and writes it,
// verbatim, into the migration that loads it (between the $fields$ markers), so the database, the OpenAPI field lists and the developer guide
// all come from one file.
//   node scripts/api-v3-field-dictionary.mjs check                 validate the list
//   node scripts/api-v3-field-dictionary.mjs embed <migration.sql>  validate, then write the list into the migration
//   node scripts/api-v3-field-dictionary.mjs markdown [surface]     print the field tables for the developer guide
import fs from 'node:fs'

const FILE = 'docs/api/v3/field-dictionary.json'
const TYPES = new Set(['string', 'integer', 'number', 'boolean', 'date', 'timestamptz', 'object', 'array<string>', 'array<object>'])
const SURFACES = new Set(['website', 'zoho', 'shared'])

export function load(file = FILE) {
  return JSON.parse(fs.readFileSync(file, 'utf8'))
}

export function validate(doc) {
  const errs = []
  if (!doc || !Array.isArray(doc.fields) || doc.fields.length === 0) return ['fields must be a non-empty list']
  const seen = new Set()
  const byKey = new Map()
  doc.fields.forEach((f, i) => {
    const at = `entry ${i + 1} (${f?.api_surface} ${f?.endpoint} ${f?.field_path})`
    if (!SURFACES.has(f.api_surface)) errs.push(`${at}: api_surface`)
    if (!f.endpoint || !f.field_path) errs.push(`${at}: endpoint and field_path are required`)
    if (!TYPES.has(f.data_type)) errs.push(`${at}: data_type ${f.data_type}`)
    if (typeof f.is_nullable !== 'boolean') errs.push(`${at}: is_nullable`)
    if (!f.description || !String(f.description).trim()) errs.push(`${at}: description`)
    if (f.allowed_values != null && !Array.isArray(f.allowed_values)) errs.push(`${at}: allowed_values must be a list`)
    if (f.req_ids != null && (!Array.isArray(f.req_ids) || f.req_ids.some((r) => !/^REQ-\d+$/.test(r)))) errs.push(`${at}: req_ids must be REQ-n`)
    const k = `${f.api_surface}|${f.endpoint}|${f.field_path}`
    if (seen.has(k)) errs.push(`${at}: listed twice`)
    seen.add(k)
    byKey.set(k, f)
  })
  // every nested path has its parent listed, and the parent is an object or a list of objects
  for (const f of doc.fields) {
    const p = f.field_path
    const cut = p.lastIndexOf('.')
    if (cut > 0) {
      const parent = p.slice(0, cut).replace(/\[\]$/, '')
      const pf = byKey.get(`${f.api_surface}|${f.endpoint}|${parent}`)
      if (!pf) errs.push(`${f.api_surface} ${f.endpoint} ${p}: parent ${parent} is not listed`)
      else if (!['object', 'array<object>'].includes(pf.data_type)) errs.push(`${f.api_surface} ${f.endpoint} ${p}: parent ${parent} is ${pf.data_type}`)
    }
  }
  return errs
}

export function serialise(doc) {
  return JSON.stringify(doc, null, 1) + '\n'
}

// The form embedded in the migration: each description once, each field one short row
// [surface (w website, z zoho, s shared), endpoint, field_path, data_type, is_nullable (1/0), description index, allowed_values or 0, req_ids or 0].
export function compact(doc) {
  const desc = [...new Set(doc.fields.map((f) => f.description))]
  const at = new Map(desc.map((d, i) => [d, i]))
  const rows = doc.fields.map((f) => [f.api_surface[0], f.endpoint, f.field_path, f.data_type, f.is_nullable ? 1 : 0, at.get(f.description),
    f.allowed_values ?? 0, f.req_ids && f.req_ids.length ? f.req_ids : 0])
  return '{"d":' + JSON.stringify(desc) + ',\n"f":[\n' + rows.map((r) => JSON.stringify(r)).join(',\n') + '\n]}'
}

export function embedded(sql) {
  const m = sql.match(/\n\$fields\$\n([\s\S]*?)\n\$fields\$\)/)
  return m ? m[1] : null
}

export function markdown(doc, surface) {
  const out = []
  const eps = [...new Set(doc.fields.filter((f) => !surface || f.api_surface === surface).map((f) => `${f.api_surface}|${f.endpoint}`))]
  for (const e of eps) {
    const [s, ep] = e.split('|')
    out.push(`### ${s === 'zoho' ? 'Zoho' : 'Website'} \`${ep}\``, '', '| Field | Type | Null | Description |', '|---|---|---|---|')
    for (const f of doc.fields.filter((x) => x.api_surface === s && x.endpoint === ep && !x.deprecated_in)) {
      const allowed = f.allowed_values ? ` Values: ${f.allowed_values.map((v) => `\`${v}\``).join(', ')}.` : ''
      out.push(`| \`${f.field_path}\` | ${f.data_type} | ${f.is_nullable ? 'yes' : 'no'} | ${String(f.description).replace(/\|/g, '\\|')}${allowed} |`)
    }
    out.push('')
  }
  return out.join('\n')
}

if (process.argv[1] && import.meta.url.endsWith(process.argv[1].split('/').pop())) {
  const [cmd, arg] = process.argv.slice(2)
  const doc = load()
  const errs = validate(doc)
  if (errs.length) { console.error(errs.join('\n')); process.exit(1) }
  if (cmd === 'check' || !cmd) {
    console.log(`ok: ${doc.fields.length} fields`)
  } else if (cmd === 'embed') {
    const sql = fs.readFileSync(arg, 'utf8')
    const body = compact(doc)
    if (body.includes('$fields$')) { console.error('the list must not contain $fields$'); process.exit(1) }
    const next = sql.replace(/\n\$fields\$\n[\s\S]*?\n\$fields\$\)/, `\n$fields$\n${body}\n$fields$)`)
    fs.writeFileSync(arg, next)
    console.log(`embedded ${doc.fields.length} fields into ${arg}`)
  } else if (cmd === 'markdown') {
    process.stdout.write(markdown(doc, arg))
  } else {
    console.error('usage: check | embed <migration.sql> | markdown [surface]'); process.exit(1)
  }
}
