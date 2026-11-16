// Guards: Prompt registry in shadow (Phase 2 wave C of the UI/UX and settings simplification, Platform Admin 16 Nov 2026 05:23; architectural spec §7.1): each registered prompt is today's prompt verbatim (the course description system text equals the worker constant and its sha-256; the provider description and scholarship prompts are copied from their active database rows), its answer schema equals the worker's, its user template renders exactly the worker's message, undeclared or missing variables fail, the status can only be shadow or retired, and no worker or function reads the registry
// CF-247 S553. Migration 20261116050000_cf247_prompt_registry_shadow; supabase/functions/coverage-sweep/course-text.ts and description.ts.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const M = fs.readFileSync('supabase/migrations/20261116050000_cf247_prompt_registry_shadow.sql', 'utf8')
const CT = fs.readFileSync('supabase/functions/coverage-sweep/course-text.ts', 'utf8')
const DS = fs.readFileSync('supabase/functions/coverage-sweep/description.ts', 'utf8')
const lit = (src) => new Function(`return (${src})`)()

test('course description: the registered system text is the worker constant, byte for byte, with the worker’s sha-256', () => {
  // v1.0.5 (s559): cdesc-source-grounded-v3 is the worker's CDESC_SYSTEM and is registered by migration 20261116090000; v2 is kept as CDESC_SYSTEM_V2
  const M3 = fs.readFileSync('supabase/migrations/20261116090000_cf247_cdesc_v3_retry_gate_telemetry.sql', 'utf8')
  for (const [constName, shaName, version, src] of [['CDESC_SYSTEM', 'CDESC_SYSTEM_SHA256', 'cdesc-source-grounded-v3', M3], ['CDESC_SYSTEM_V2', 'CDESC_SYSTEM_V2_SHA256', 'cdesc-source-grounded-v2', M]]) {
    const worker = JSON.parse(new RegExp(`^export const ${constName} = ("(?:[^"\\\\]|\\\\.)*");$`, 'm').exec(CT)[1])
    const sha = new RegExp(`^export const ${shaName} = "([0-9a-f]{64})"`, 'm').exec(CT)[1]
    const reg = new RegExp(`'${version}', \\$cdesc\\$([\\s\\S]*?)\\$cdesc\\$, '([0-9a-f]{64})'`).exec(src)
    expect(reg[1], version).toBe(worker)
    expect(reg[2], version).toBe(sha)
    expect(crypto.createHash('sha256').update(reg[1], 'utf8').digest('hex')).toBe(sha)
  }
  expect(/^export const CDESC_PROMPT_VERSION = "cdesc-source-grounded-v3";$/m.test(CT)).toBe(true)
})

test('answer schemas equal the worker’s; the provider description user template renders the worker’s message', () => {
  const cdesc = lit(/export function cdescSchema\(\) \{\n  return (\{[\s\S]*?\});\n\}/.exec(CT)[1])
  const pdesc = lit(/export const PROMPT_SCHEMA = (\{[\s\S]*?\}) as const;/.exec(DS)[1])
  const schemas = [...M.matchAll(/'(\{"type": "object"[^']*\})'::jsonb/g)].map((m) => JSON.parse(m[1]))
  expect(schemas).toContainEqual(cdesc)
  expect(schemas).toContainEqual(pdesc)
  // the worker: `Provider: ${provider}\nPage: ${url}\n${lengthNote(length)}\nPage text:\n${page}`
  const tpl = /content: `(Provider: \$\{provider\}\\nPage: \$\{url\}\\n\$\{lengthNote\(length\)\}\\nPage text:\\n\$\{page\})` \}/.exec(DS)[1]
  const v = { provider: 'P', url: 'U', length_note: 'L', page_text: 'T' }
  const worker = tpl.replace('${provider}', v.provider).replace('${url}', v.url).replace('${lengthNote(length)}', v.length_note).replace('${page}', v.page_text).replace(/\\n/g, '\n')
  const reg = /E'(Provider: \{\{provider\}\}\\nPage: \{\{url\}\}\\n\{\{length_note\}\}\\nPage text:\\n\{\{page_text\}\})'/.exec(M)[1]
  const rendered = reg.replace(/\\n/g, '\n').replace(/\{\{([a-z_]+)\}\}/g, (_, k) => v[k])
  expect(rendered).toBe(worker)
  expect(M).toContain("array['provider', 'url', 'length_note', 'page_text']")
})

test('database prompts are copied from their active rows; render and answer checks refuse what does not fit', () => {
  expect(M).toContain("from pipeline.provider_description_prompts p where p.status = 'active'")
  expect(M).toContain('from pipeline.scholarship_ai_prompts p where p.active')
  expect(M).toContain("raise exception 'prompt % %: placeholder {{%}} is not declared'")
  expect(M).toContain("raise exception 'prompt % %: variable % is not given'")
  expect(M).toContain("raise exception 'post-check: a missing variable did not fail';")
  expect(M).toContain("raise exception 'post-check: an answer missing required keys passed the schema';")
  expect(M).toContain("raise exception 'post-check: parity failed: %', v_p;")
})

test('shadow only: no live status, and nothing in the worker or another migration reads the registry', () => {
  expect(M).toContain("status text not null default 'shadow' check (status in ('shadow', 'retired'))")
  const files = (d) => fs.readdirSync(d, { recursive: true }).filter((f) => /\.(ts|js|mjs)$/.test(f)).map((f) => `${d}/${f}`)
  for (const f of files('supabase/functions')) expect(fs.readFileSync(f, 'utf8'), f).not.toMatch(/prompt_templates|prompt_render_v1/)
  // a migration that releases a prompt keeps the registry in step (20261116090000: course description v3 registered, v2 retired there); it writes rows, nothing reads them
  const KEEPS_REGISTRY = ['20261116050000_cf247_prompt_registry_shadow.sql', '20261116090000_cf247_cdesc_v3_retry_gate_telemetry.sql']
  for (const f of fs.readdirSync('supabase/migrations').filter((x) => x.endsWith('.sql') && !KEEPS_REGISTRY.includes(x)))
    expect(fs.readFileSync(`supabase/migrations/${f}`, 'utf8'), f).not.toMatch(/prompt_templates/)
  expect(M).not.toMatch(/entry_matrices'|course_entry_requirements'/)
})
