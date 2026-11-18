// Guards: University description restore pdesc-reread-p5-restore (Platform Admin 19 Nov 2026 06:49 item 1): a description sent back to the reader whose re-read was held is returned to Layer 4 exactly as it was (item pending, its own reading proposed) only when the provider still has no description, no manual lock, no pending item and no open read; the migration admits nothing, writes no description and adds no function, job, table or column.
// CF-247 S761. Migration 20261119080000_cf247_pdesc_prompt_record_and_held_reread_restore. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations/20261119080000_cf247_pdesc_prompt_record_and_held_reread_restore.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('only items superseded by the re-read whose new read was held, for providers still without a description', () => {
  expect(code).toContain("and i.layer2_state->>'superseded_by' = 'pdesc-reread-p5'")
  expect(code).toContain("and p.lifecycle_status = 'active' and nullif(btrim(p.description), '') is null")
  expect(code).toContain("l.field in ('description', 'p_description', 'all'))")
  expect(code).toContain("x.field_code = 'provider_description' and x.status = 'pending')")
  expect(code).toContain("r.state in ('queued', 'reading', 'proposed'))")
  expect(code).toContain("order by r.created_at desc limit 1) = 'held';")
})

test('the item is pending and its own reading proposed again; both are proved after', () => {
  expect(code).toContain("set state = 'proposed', rule = 'missing', updated_at = now()")
  expect(code).toContain("set status = 'pending', decided_at = null,")
  expect(code).toContain("raise exception 'post-check: a restored item is not pending with its reading proposed';")
  expect(code).toContain("raise exception 'post-check: a provider has two open reads';")
  expect(code).toContain("raise exception 'post-check: an item was restored for a provider that already has a description';")
})

test('nothing is admitted or written to a provider, and nothing is created or dropped', () => {
  expect(code).not.toMatch(/update catalogue\.|insert into catalogue\.|machine_admit|state = 'admitted'|status = 'approved'/)
  expect(code).not.toMatch(/create (or replace )?function|cron\.schedule|create table|alter table|add column/i)
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|schema|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
})
