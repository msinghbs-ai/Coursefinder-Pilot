// Guards: Platform Admin 19 Nov 2026 15:18 AEDT (chat S1-Build, s775; IQ-00426): no-page-propose stays inside the 120-second statement limit. security.bind_match_scope_refresh_v1 groups the unlinked Australian courses by provider first and checks the focus rule once per provider, stopping at bind.match_scope_top_n providers that pass (tranche overrides kept as before); the partial index enrichment_flags_provider_raised_idx serves security.flag_provider_held_v1.
// The live rolled-back dry run (label live-dry-run) runs the migration's pre- and post-checks against production (scope 1.3 s, the whole job 4.5 s on 19 Nov 2026); these checks keep the rules in the file.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationPath } from './support/migration-files.mjs'

const m = fs.readFileSync(migrationPath('20261119160000_cf247_s775_no_page_scope_per_provider.sql'), 'utf8')
const c = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const f = c.slice(c.indexOf('create or replace function security.bind_match_scope_refresh_v1('), c.indexOf('$function$;', c.indexOf('create or replace function security.bind_match_scope_refresh_v1(')))

test('the refresh is replaced only from the definition that was read; one partial index, nothing dropped or deleted', () => {
  expect(c).toContain("<> '752a2ae75ca9ae3965ecbb6b520f7738' then")
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: nothing/m)
  expect(c).toContain("create index if not exists enrichment_flags_provider_raised_idx\n  on pipeline.enrichment_flags (provider_id, reason_code) where state = 'raised' and entity = 'provider';")
  expect(c).toContain('comment on index pipeline.enrichment_flags_provider_raised_idx is')
  expect(c).not.toMatch(/\b(create\s+(temp\w*\s+|unlogged\s+)?table|drop\s+(table|function|index)|truncate|delete\s+from|alter\s+table|concurrently)\b/i)
})

test('the focus rule runs once per provider, in order, until the top N have passed; overrides are kept', () => {
  expect(f).toContain("v_top int := security.pipeline_num_v1('bind.match_scope_top_n', 100)::int;")
  expect(f).toContain('with u as materialized (')
  expect(f).toContain('group by c.provider_id),')
  expect(f).toContain('select s.provider_id from (select u.provider_id, u.unbound from u order by u.unbound desc offset 0) s')
  expect(f).toContain('where not security.enrich_focus_v1(s.provider_id) limit v_top),')
  expect(f).toContain("or (u.provider_id in (select provider_id from ovr) and not security.enrich_focus_v1(u.provider_id)))")
  expect(f).toContain("on conflict (provider_id) do update set why = excluded.why, unbound = excluded.unbound, refreshed_at = now();")
  expect(f.match(/security\.enrich_focus_v1\(/g)).toHaveLength(2)
  expect(c).toContain("raise exception 'post-check: no-page-propose took % ms'")
})
