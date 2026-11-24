// Guards: Admin #966 / AER-FU-04 (AU AER Steps 1-2 only: source registration, no reader, rule, cron or admission change); G3 frozen surface; Standing Authority Charter item 2 (Tier 1 fetch)
import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';

const sql = readFileSync('supabase/migrations/20261126023000_cf247_s1096_au_aer_source_acquisition_returned_providers_wave2_and_kent_reregister.sql', 'utf8');

test('s1096 registers AU sources only, through the existing table', () => {
  expect(sql).toContain("k.iso_alpha2 = 'AU'");
  expect(sql).toContain('insert into pipeline.entry_matrix_sources');
  expect(sql).toContain('on conflict (provider_id, url) do nothing');
  expect(sql).toMatch(/-- Replaces: none\. Retires: none\./);
});

test('s1096 changes no reader, rule, setting, cron or consumer function', () => {
  expect(sql).not.toMatch(/create (or replace )?function|alter function|cron\.schedule|update pipeline\.platform_toolset_settings|public\.website_|zoho_/i);
});
