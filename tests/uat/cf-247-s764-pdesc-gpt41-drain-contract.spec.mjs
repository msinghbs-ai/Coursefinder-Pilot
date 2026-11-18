// Guards: Provider description drain pdesc-gpt41-drain (Platform Admin 19 Nov 2026 07:39 decision 2): one read is queued only for a published, active provider with no description, no manual lock and no open read, whose latest read was held by grounding or by the page identity proof, or that was never read and has a stored official page; the migration admits nothing and writes no description, so the reader's checks and the unchanged machine admission decide.
// CF-247 S764. Migration 20261119090000_cf247_pdesc_route_gpt41_mini_stored_page_drain. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations/20261119090000_cf247_pdesc_route_gpt41_mini_stored_page_drain.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('only providers with no description, no lock and no open read', () => {
  expect(code).toContain("where p.lifecycle_status = 'active' and p.publication_status = 'published' and nullif(btrim(p.description), '') is null")
  expect(code).toContain("l.field in ('description', 'p_description', 'all'))")
  expect(code).toContain("r.state in ('queued', 'reading', 'proposed'))),")
})

test('three bases: grounding holds, identity holds, and never-read providers with a stored page', () => {
  expect(code).toContain("lr.rule in ('quote_not_on_page', 'unsupported_sentence', 'unsupported_numeric_claim', 'provider_name_conflict', 'provider_name_not_proved')")
  expect(code).toContain('and security.provider_description_stored_v1(m.id) is not null;')
  expect(code).toContain("jsonb_build_object('drain', jsonb_build_object('rule', 'pdesc-gpt41-drain', 'basis', c.basis, 'at', now()))")
})

test('nothing is admitted or written to a provider, and no on-demand mark lifts a limit', () => {
  expect(code).not.toMatch(/update catalogue\.|insert into catalogue\.|machine_admit|state = 'admitted'|status = 'approved'|on_demand/)
  expect(code).toContain("raise exception 'post-check: a provider has two open reads';")
  expect(code).toContain("raise exception 'post-check: a provider with a description was queued';")
})
