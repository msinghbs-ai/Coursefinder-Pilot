import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// Decision 162 step 1: course attribute badges come from stored records, not presence guesses.
test('Field states read stored provenance and only await layers that really have work',()=>{
  const m=fs.readFileSync('supabase/migrations/20260928160000_d162_course_field_states_provenance.sql','utf8')
  expect(m).toContain("if md5(pg_get_functiondef('security.admin_course_field_states(uuid)'::regprocedure))<>'d063f16247b06302895bde812fb8f6dd'")
  expect(m).toContain("where w.entity_id=c.id and w.status='admitted' and w.evidence_id=v_fee.evidence_id")   // Layer 3 from the admitted work item
  expect(m).toContain("elsif 'international_fee'=any(v_domains) then")                                         // awaiting L2 only with a qualified source
  expect(m).toContain("'value_state','l1_covers','resolved_layer',1")                                          // CRICOS tuition applies
  expect(m).toContain("upper(btrim(q.provider_cricos))=any(v_codes)")                                          // provider-scoped (Decision 149)
  expect(m).not.toContain('v_try_intakes')                                                                     // no more "Awaiting L3" guesses
  const ui=fs.readFileSync('src/CourseDetailPolish.jsx','utf8')
  expect(ui).toContain("if(s==='l1_covers')return")
  expect(ui).toContain("if(s==='not_collected')return")
  expect(ui).toContain('title={state?.resolved_by||undefined}')
})
