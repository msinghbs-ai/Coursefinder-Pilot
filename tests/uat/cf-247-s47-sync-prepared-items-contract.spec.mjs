// CF-247 (S47): Platform Admin 15 Oct 2026 17:46: "How can we burst it for wix"; decision "Prepared items + bigger pages". The change check keeps
// the item it built (its hash is of that copy); sync serves it and fills a page by size; pages hold up to 200 items.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const mig = fs.readFileSync('supabase/migrations/20261015100000_cf247_sync_prepared_items.sql', 'utf8')
test('the change check stores the item; sync serves it by size; page max 200 is a setting', () => {
  expect(mig).toContain('alter table pipeline.website_sync_items add column if not exists item jsonb;')
  expect(mig).toContain("update pipeline.website_sync_items set hash = h, item = v, ref_id = r.ref_id, seq = nextval('pipeline.website_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;")
  expect(mig).toContain("coalesce(nullif(r->'item', 'null'::jsonb), security.website_sync_item_v1(")
  expect(mig).toContain("when y.item is not null then greatest(ceil(octet_length(y.item::text)::numeric / v_unit), 1)::int")
  expect(mig).toContain("set value = to_jsonb(200)")
  expect(mig).toContain("('pipeline', 'website.sync_item_unit_bytes',")
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
