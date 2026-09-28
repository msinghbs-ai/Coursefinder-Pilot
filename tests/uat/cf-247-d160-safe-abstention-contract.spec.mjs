import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// Decision 160: Layer 3 qualification accepts safe abstention but never an uncaught wrong answer.
test('Layer 3 tuition qualification: zero unsafe, conclusive, useful; activation stays separate',()=>{
  const m=fs.readFileSync('supabase/migrations/20260928100000_d160_layer3_safe_abstention_qualification.sql','utf8')
  expect(m).toContain("v_provider_ok:=v_cases>=3 and v_unsafe=0 and v_infra=0 and v_resolved>=3 and v_resolved*2>=v_cases;")
  expect(m).toContain("'qualification_rule','decision_160_safe_abstention'")
  expect(m).toContain("'profile_paused',true")   // a pass never activates by itself
  expect(m).toContain('33ed315e5208a6b09ba4d195971947bb')
})
