import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// A settings-only Layer 2 profile version must never empty scheduled extraction again.
test('New profile versions with unchanged discovery settings inherit discovered course URLs',()=>{
  const m=fs.readFileSync('supabase/migrations-archive/20260928130000_layer2_discovery_candidates_carry_forward.sql','utf8')
  expect(m).toContain('create trigger trg_layer2_profile_version_carry_forward after insert on pipeline.layer2_source_profile_versions')
  expect(m).toContain("(v_new.configuration->'discovery_strategy') is distinct from (v_old.configuration->'discovery_strategy')")
  expect(m).toContain("(v_new.configuration->'url_patterns') is distinct from (v_old.configuration->'url_patterns')")
  expect(m).toContain("'carried_forward_from_version',v_old.id")
  expect(m).toContain("if v_total<>7301 or v_profiles<>141 then raise exception")
})
