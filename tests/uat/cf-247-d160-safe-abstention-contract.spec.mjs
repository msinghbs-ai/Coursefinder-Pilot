import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// Decision 160: Layer 3 qualification accepts safe abstention but never an uncaught wrong answer.
test('Layer 3 tuition qualification: zero unsafe, conclusive, useful; activation stays separate',()=>{
  const m=fs.readFileSync('supabase/migrations-archive/20260928100000_d160_layer3_safe_abstention_qualification.sql','utf8')
  expect(m).toContain("v_provider_ok:=v_cases>=3 and v_unsafe=0 and v_infra=0 and v_resolved>=3 and v_resolved*2>=v_cases;")
  expect(m).toContain("'qualification_rule','decision_160_safe_abstention'")
  expect(m).toContain("'profile_paused',true")   // a pass never activates by itself
  expect(m).toContain('33ed315e5208a6b09ba4d195971947bb')
})

test('Open items on a profile that cannot run are moved to the qualified profile, with an audit row',async()=>{
  const m=fs.readFileSync('supabase/migrations-archive/20260928100100_d160_layer3_rebind_open_items.sql','utf8')
  expect(m).toContain('create table if not exists pipeline.layer3_work_item_rebinds(')
  expect(m).toContain("if v_n<>1 then raise exception 'expected exactly one qualified active tuition profile")
  expect(m).toContain("and w.status in ('pending','failed')")            // finished items are never moved
  expect(m).toContain('and (not p.enabled or p.paused)')
})
