// CF-247 Decision 225 (v2.15.152): tuition comes from the regulator where it publishes it (Australia: CRICOS);
// provider-page tuition is chased only for countries whose regulator publishes none, for international students.
import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'

test('migration: AU tuition list emptied, fee schedules gated, AU tuition work parked and reviews closed', async () => {
  const m = await fs.readFile('supabase/migrations/20261002182600_cf247_au_tuition_from_cricos.sql', 'utf8')
  expect(m).toContain("jsonb_build_object('tuition', '[]'::jsonb)")
  expect(m).toContain("k.iso_alpha2 = 'AU'")
  expect(m).toContain('create or replace function security.tuition_chase_enabled')
  for (const g of ['8877b60844b77f8d465a81dc3859134a', 'a028891bb3f7ecf2ad7fed585eeac76a']) expect(m).toContain(g)
  expect(m).toContain("(s.kind <> 'fee_schedule' or security.tuition_chase_enabled(s.provider_id))")
  expect(m).toContain("set status = 'parked'")
  expect(m).toContain("'ref', 'Decision 225'")
  expect(m).not.toMatch(/\bdrop\s|delete\s+from|truncate/i)
})

test('History shows the CRICOS tuition for Australia', async () => {
  const ui = await fs.readFile('src/layer2-operations-entry.jsx', 'utf8')
  expect(ui).toContain("c==='AU'?[...FACTS.slice(0,3),['registered_tuition','Tuition (CRICOS)']]:FACTS")
})
