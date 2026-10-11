// CF-247 Phase 3 (Platform Admin 9 Oct 2026): the merged adapter step runs side by side with Layer 3 and admits nothing.
// v2.15.252 (Platform Admin, 12 Oct 2026): Layer 3 retired; layer3-model-routing and _shared/cf247-adapter-shadow.ts were
// deleted, so the checks that read them were removed. The archived migrations are still checked.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('migration: limits, retire test reported only, nothing deleted, nothing admitted', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261008005300_cf247_phase3_adapter_shadow.sql', 'utf8')
  expect(m).toContain('daily_usd_max numeric not null default 15')
  expect(m).toContain('daily_reads_max int not null default 1000')
  expect(m).toContain('retire_match numeric not null default 0.95')
  expect(m).toContain("and t.agree_n::numeric / t.both_found >= s.retire_match and t.shadow_found_n >= t.layer3_found_n")
  expect(m).toContain("if v_spent >= s.daily_usd_max then")
  expect(m).not.toMatch(/delete\s+from|drop\s+(table|function|schema)|truncate/i)
  expect(m).not.toMatch(/svc_coursefacts_apply_record|layer3_fact_admit/)
  expect(m).toContain("cron.schedule('adapter-shadow-intake'")
  expect(m).toContain("cron.schedule('adapter-shadow-english'")
})

test('tuition: the task contract and checks come from the tuition profile (migration)', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261008005400_cf247_phase3_shadow_tuition_capacity.sql', 'utf8')
  expect(m).toContain("if md5(pg_get_functiondef(k::regprocedure)) <> v then raise exception")
  expect(m).toContain("check (task in ('intake','english','tuition'))")
  expect(m).toContain("v_tp := (select to_jsonb(p) from pipeline.layer3_routed_profile(v_class) p where p.id is not null);")
  expect(m).toContain("round((a->>'amount')::numeric) = round((b->>'amount')::numeric)")
  expect(m).toContain('daily_reads_max = 1500')
  expect(m).toContain("cron.schedule('adapter-shadow-tuition'")
  expect(m).not.toMatch(/delete\s+from|drop\s+(table|function|schema)|truncate/i)
  expect(m).not.toMatch(/svc_coursefacts_apply_record|layer3_fact_admit|tuition_admit/)
})

test('round 2: stronger adapter model for the shadow run only; rounds kept apart; md5-guarded; nothing deleted', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261008005500_cf247_phase3_round2_stronger_model.sql', 'utf8')
  expect(m).toContain("set round = 2, model_profile_code = 'openrouter-intake-l3c-mimo-v2-6-pro-v1'")
  expect(m).toContain("where p.code = coalesce(s.model_profile_code, security.adapter_builder_model_for_v1(r.provider_id)->>'code')")
  expect(m).toContain("from t, s where t.round = s.round), '[]'::jsonb),")
  expect(m).toContain("'earlier_rounds'")
  expect(m).toContain("if md5(pg_get_functiondef(k::regprocedure)) <> v then raise exception")
  expect(m).not.toMatch(/delete\s+from|drop\s+|truncate/i)
  expect(m).not.toMatch(/uni_adapter_models|svc_coursefacts_apply_record|layer3_fact_admit/)
})

test('round 3: adapter model first, one escalation only when nothing was found and the page clearly shows the field', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261008005700_cf247_phase3_round3_escalation.sql', 'utf8')
  expect(m).toContain("set round = 3, model_profile_code = null, escalation_profile_code = 'openrouter-intake-l3c-mimo-v2-6-pro-v1'")
  expect(m).toContain("'profile', v_prof, 'escalation', v_esc);")
  expect(m).toContain("escalated = coalesce((p_result->>'escalated')::boolean, false)")
  expect(m).toContain("if md5(pg_get_functiondef(k::regprocedure)) <> v then raise exception")
  expect(m).not.toMatch(/delete\s+from|drop\s+|truncate/i)
})

test('Phase 3 closes: shadow jobs removed only after the run is switched off; the record is kept', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261008005800_cf247_phase3_close_shadow_jobs.sql', 'utf8')
  expect(m).toContain("raise exception 'the shadow run is still switched on; switch it off first'")
  for (const j of ['adapter-shadow-intake', 'adapter-shadow-english', 'adapter-shadow-tuition']) expect(m).toContain(`'${j}'`)
  expect(m).not.toMatch(/delete\s+from|drop\s+|truncate/i)
})
