// CF-247 (S54): Layer 4 approvals for English and course links. Platform Admin 17 Oct 2026 16:19: "Bring everything from layer 4 and assess
// either for rule or ai extraction and proceed or give me recomemded choices". Found: an English item could never be approved; a course link
// proposed as course_url could not be approved.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261017050000_cf247_layer4_english_and_link_approve.sql', 'utf8')

test('English decisions write the requirement and lock it as a person\'s decision; links read url or course_url; md5-guarded', () => {
  expect(mig).toContain("elsif v_item.field_code='course_english' then")
  expect(mig).toContain("v_scalar:=security.layer4_course_english_apply_impl(v_actor,v_item.id,v_final,trim(p_reason));")
  expect(mig).toContain("'l4:' || v_item.id || ':' || lower(coalesce(x->>'test_code', x->>'test'))")
  expect(mig).toContain("values ('course', v_item.entity_id, 'english', 'value', p_actor)")
  expect(mig).toContain("coalesce(p_value->>'url', p_value->>'course_url')")
  expect(mig).toContain("<> 'dae40e946183598c2e6a4be9843d16fb' then")
  expect(mig).toContain("<> '5b9c4ce104f96ba4136a3ad2e8f8440e' then")
  expect(mig).not.toMatch(/^\s*(delete|drop)\b/im)
})
