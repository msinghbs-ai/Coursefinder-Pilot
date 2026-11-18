// Guards: S3-Boost providers (Platform Admin 18 Nov 2026): deterministic CRICOS provider website normalisation and report-only reconciliation.
import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { normaliseCricosProviderWebsite } from '../../supabase/functions/_shared/cf247-cricos-provider-website.mjs'
import { applySpec } from '../../supabase/functions/_shared/cf247-layer1-spec.ts'
import { reconcileProviders } from '../../scripts/boost-cricos-provider-audit.mjs'

test('bare CRICOS DNS names receive HTTPS and explicit HTTP(S) addresses keep their path and scheme', () => {
  expect(normaliseCricosProviderWebsite(' www.mq.edu.au ')).toBe('https://www.mq.edu.au')
  expect(normaliseCricosProviderWebsite('provider.edu.au:8443/path?a=1#contact')).toBe('https://provider.edu.au:8443/path?a=1#contact')
  expect(normaliseCricosProviderWebsite('http://www.tafesa.edu.au/international')).toBe('http://www.tafesa.edu.au/international')
  expect(normaliseCricosProviderWebsite('https://anglischools.edu.au/international/')).toBe('https://anglischools.edu.au/international/')
})

test('bad or missing input stays empty and the declarative behaviour applies only to CRICOS provider websites', () => {
  for (const input of [null, '', 'www', 'https:///provider.edu.au', 'bad host.edu.au', '//provider.edu.au', 'ftp://provider.edu.au', 'https://person@provider.edu.au', 'provider.edu.au\\path', 'provider.edu.au:bad']) {
    expect(normaliseCricosProviderWebsite(input)).toBeNull()
  }
  const parser = { record_type: 'provider_register', fields: [{ source: 'Website', target: 'website', type: 'url' }] }
  const rows = [{ Website: 'www.mq.edu.au' }]
  expect(applySpec(parser, rows, 20, 'cricos')).toEqual({ records: [{ website: 'https://www.mq.edu.au' }], errors: [] })
  expect(applySpec(parser, rows, 20, 'nzqa').records).toEqual([{ website: null }])
  expect(applySpec({ ...parser, record_type: 'course_register' }, rows, 20, 'cricos').records).toEqual([{ website: null }])
})

test('the audit counts distinct source rows, preserves alias candidates, and ignores scheme and www when comparing domains', () => {
  const result = reconcileProviders([
    { code: '00017B', legal: 'Bond University', trading: 'Bond University Limited', website: 'www.bond.edu.au' },
    { code: '00057E', legal: 'Alexander Language School Pty Ltd', trading: 'Alexander Language School', website: 'https://anglischools.edu.au/international/' },
    { code: '00099F', legal: 'Example University', trading: '', website: 'example.edu.au' },
  ], [
    { code: '00017B', id: 'bond', registration_status: 'active', lifecycle_status: 'active', website: 'http://bond.edu.au', display_name: 'Bond University Limited' },
    { code: '00057E', id: 'alexander', registration_status: 'active', lifecycle_status: 'active', website: 'https://www.sgis.wa.edu.au', display_name: 'Alexander Language School' },
    { code: '00099F', id: 'example', registration_status: 'active', lifecycle_status: 'active', website: null, display_name: 'Example University' },
  ], [
    { code: '00017B', provider_id: 'bond', alias: 'Bond University', kind: 'legal' },
    { code: '00017B', provider_id: 'another', alias: 'Bond University', kind: 'legal' },
  ])
  expect(result.telemetry).toMatchObject({ sample_size: 3, matched_exact: 3, alias_candidates_found: 1, domain_mismatch_count: 1, missing_url_count: 1, bare_scheme_urls_normalised: 2 })
  expect(result.domain_mismatches.map(row => row.code)).toEqual(['00057E'])
  expect(result.alias_candidates.map(row => row.same_provider)).toEqual([true, false])
})

test('archive replay and wizard map, preview, and apply share the CRICOS provider website rule', () => {
  const archive = readFileSync('supabase/functions/_shared/cf247-register-zip.ts', 'utf8')
  const mapper = readFileSync('supabase/functions/layer1-ai-induction-mapper/index.ts', 'utf8')
  const runner = readFileSync('supabase/functions/layer1-declarative-runner/index.ts', 'utf8')
  expect(archive).toContain('name === "provider_website" ? (normaliseCricosProviderWebsite(value) ?? "")')
  expect(mapper).toContain('applySpec(parser_spec, objects, 10, p.scheme)')
  expect(mapper).toContain('scheme: clean(draft?.payload?.scheme, 40)')
  expect(mapper).toContain('scheme: clean(induction?.payload?.scheme, 40)')
  expect(runner).toContain('applySpec(spec, table.rows, undefined, clean(p.scheme, 40))')
  expect(runner).toContain('applySpec(spec, slice, undefined, scheme)')
})
