// Guards: Platform Admin 26 Nov 2026 03:59 AEDT (resolve technical exceptions automatically; preserve safeguards and spending limits) and Window 2 approval (25 Nov 2026 14:36 and 18:26 AEDT)
// s1157: corrections whose Layer 4 item is superseded are skipped without a read ($0); only the genuine remainder is read under the Window 2 containment.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261128200000_cf247_s1157_entry_window2_remainder.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1157: only a correction whose Layer 4 item is no longer pending is skipped, with its reason', () => {
  expect(MIG).toContain("where w.reason like 'Corrected read (D-R2) of Layer 4 item %' and w.tgt is not null")
  expect(MIG).toContain("not exists (select 1 from pipeline.layer4_review_items l where l.id = w.tgt and l.status = 'pending')")
  expect(MIG).toContain("reason = 'corrected read (D-R2) not read: its Layer 4 item is no longer pending (superseded); a read would be refused when recorded'")
  expect(MIG).toContain("where f.id in (select id from s1157_keep) and f.state = 'leased' and f.leased_until < now()")
})

test('s1157: the genuine remainder is read under the same containment; nothing is deleted, admitted or scheduled', () => {
  expect(MIG).toContain("if (select count(*) from s1157_keep) > 10 then raise exception")
  expect(MIG).toContain("if not exists (select 1 from pipeline.ai_route_qualifications q where q.service_code = 'course_entry_requirements' and q.model_code = 'gpt-4.1-mini' and q.status = 'qualified')")
  expect(MIG).toContain("'firecrawl_credits', 0")
  for (const s of ['post-check: % entry items outside the genuine remainder could be read under an open request', 'post-check: the scheduled reader is not held by the cap',
    'post-check: a superseded correction is still waiting', 'post-check: the number of active cron jobs changed', 'post-check: manual locks changed', 'post-check: the consumer API moved']) expect(MIG).toContain(s)
  expect(code).not.toMatch(/course_entry_read_enqueue_v1|cron\.schedule|cron\.alter_job|layer4_review_items\s+set|insert into catalogue\.|\bdelete from\b|truncate /i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l) || /^alter table .* drop /i.test(l))).toEqual([])
})
