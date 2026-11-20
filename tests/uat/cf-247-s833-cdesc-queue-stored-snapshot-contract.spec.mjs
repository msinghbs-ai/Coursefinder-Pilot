// Guards: CF-247 s833 (Platform Admin 20 Nov 2026 14:24 AEDT, chat S1-Courses): the Layer 4 course description queue answers from a stored copy, falls back to the live path unchanged, never decides or writes a description, and keeps G1, G2 and G3
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261120143000_cf247_s833_cdesc_queue_stored_snapshot.sql', 'utf8')

test('housekeeping lines, no drop or delete, one table, one job, table comment', () => {
  expect(MIG).toMatch(/^-- Replaces: .+\.$/m)
  expect(MIG).toMatch(/^-- Retires: nothing\./m)
  expect(MIG).not.toMatch(/\b(drop\s+(table|function|view|index)|delete\s+from|truncate)\b/i)
  expect((MIG.match(/create table if not exists/g) || []).length).toBe(1)
  expect(MIG).toContain("comment on table pipeline.cdesc_queue_snapshot is 'CF-247 s833:")
  expect(MIG).toContain("select cron.schedule('cdesc-queue-refresh'")
  expect(MIG).toContain("insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values\n ('cdesc-queue-refresh'")
})

test('the queue reads the stored copy only for the default call and falls back to the live functions', () => {
  expect(MIG).toContain("then security.cdesc_queue_stored_v1('summary', 0, false) end,")
  expect(MIG).toContain("security.course_description_summary_v1(nullif(a->>'provider_id', '')::uuid, coalesce((a->>'recheck')::boolean, false)))")
  expect(MIG).toContain("when 'items' then coalesce(case when nullif(a->>'provider_id', '') is null then security.cdesc_queue_stored_v1('items'")
  expect(MIG).toContain("security.course_description_items_v1(nullif(a->>'provider_id', '')::uuid, coalesce((a->>'offset')::int, 0), coalesce((a->>'sample')::boolean, false)))")
  // a card decided since the rebuild is dropped at read time
  expect(MIG).toContain("and i.status = 'pending'")
  expect(MIG).toContain("then return null; end if;")
})

test('the live path edits are fragment-guarded and read the one reading by key', () => {
  expect((MIG.match(/pg_temp\.cf_edit_def\(/g) || []).length).toBe(3 + 1)  // three calls plus the definition
  expect(MIG).toContain('left join lateral (select f.id, f.value from pipeline.field_enrich_items f where f.id = p.eid) e on true')
  expect(MIG).toContain("case when f.state = 'filled' then f.value->>'admitted' end admitted")
  expect(MIG).toContain('must occur exactly once')
})

test('nothing is decided, admitted or written to the catalogue; spend none', () => {
  expect(MIG).not.toMatch(/\b(update|insert\s+into)\s+(catalogue|search|pipeline\.layer4_|pipeline\.field_enrich_items|pipeline\.manual_locks)/i)
  expect(MIG).not.toMatch(/layer4_decide|admin_layer4_inbox\(/)
})

test('G2 and G3: the age limit is a setting, the time-outs are marked fixed, the consumer API is checked before and after', () => {
  expect(MIG).toContain("'cdesc.queue_snapshot_max_age_minutes'")
  expect(MIG).toContain("security.pipeline_num_v1('cdesc.queue_snapshot_max_age_minutes', 35)")
  expect(MIG).toMatch(/statement_timeout = '180s';\s+-- fixed:/)
  expect(MIG).toMatch(/set_config\('statement_timeout', '180s', true\);\s+-- fixed:/)
  expect((MIG.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect((MIG.match(/<> 75/g) || []).length).toBe(2)
  expect((MIG.match(/<> 48/g) || []).length).toBe(2)
})

test('post-check: both calls under 300 ms as a Platform Admin and the stored summary equals the live one', () => {
  expect(MIG).toContain('if v_s_ms > 300 or v_i_ms > 300 then raise exception')
  expect(MIG).toContain("(v_sum->'by_class') is distinct from (v_live->'by_class')")
})
