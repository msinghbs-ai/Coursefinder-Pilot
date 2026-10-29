// Guards: CF-247 AER v1.1 completeness guard at admission (Platform Admin 26 Oct 2026 23:16): under the guard a complete read is admitted whole or not at all; excluding rows, or rows missing since the verdict, refuses the approval (exclusions superseded by A1 Approve except, Platform Admin 30 Oct 2026 06:53: every row of a complete read is admitted or explicitly excluded; guarded by s176)
// Record: admin docs/platform/aer-v1.1-build-log.md. A live rolled-back probe (26 Oct 23:5x) admitted 13 of China's 22 rows with Gao Kao excluded.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261026011000_cf247_entry_matrix_complete_admission.sql', 'utf8')

test('approval admits exactly the rows the complete verdict matched; the guard and identity checks stay ahead of it', () => {
  expect(m).toContain("select pg_temp.edit_n('security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)', '9386a7be7726b5f23a3d01436dfeca35'")
  expect(m).toContain("and (select count(*) from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed' and not (m.id = any(v_ex)))")
  expect(m).toContain("is distinct from nullif(r.result->'completeness'->>'matched', '')::int then")
  expect(m).toContain("a read is admitted whole or rejected', r.id,")
  // anchored after the #709 verdict check, so a read without a complete verdict is still refused first
  expect(m).toContain("coalesce(r.result->'completeness'->>'status', 'no verdict') using errcode = '23514';\n    end if;\n    -- complete admission")
  expect(m).toContain('if security.entry_completeness_required_v1(r.provider_id)')  // providers outside the guard (UTS) unchanged
  expect(m).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})
