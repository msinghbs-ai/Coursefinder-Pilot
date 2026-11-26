// Guards: Agent Operating Model v1.29 and Master Plan §6.8, operational learning (Platform Admin 27 Nov 2026, s1292): lessons are held in the existing recovery knowledge with their favourable and adverse outcomes once each, new patterns are never automatic, an unchanged failed attempt and a protected correction are refused by the existing retry check, and Platform health shows the knowledge.
// CF-247 S1292. supabase/migrations/20261130100000_cf247_s1292_operational_learning_lessons.sql, src/ui-v1/PlatformHealthView.jsx
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations/20261130100000_cf247_s1292_operational_learning_lessons.sql', 'utf8').split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')
const view = fs.readFileSync('src/ui-v1/PlatformHealthView.jsx', 'utf8')

test('lessons reuse the existing knowledge and recorder, once per evidence signature, never automatic', () => {
  expect(code).toContain('insert into pipeline.ops_remedy_knowledge')
  expect(code).toContain('on conflict (code) do nothing')
  expect(code).toContain('o.knowledge_code = r.code and o.evidence_signature = r.sig')
  expect(code).toContain('perform security.ops_learning_record_v1(')
  expect(code).toContain("raise exception 'post-check: a new lesson became automatic'")
  expect(code).not.toMatch(/create table|cron\.schedule\(|\bdelete\s+from|\bdrop\s+(table|function)/i)
})

test('the retry check refuses an unchanged failed attempt and keeps the held consumer correction held', () => {
  expect(code).toContain("raise exception 'post-check: the unchanged failed read is not refused: %'")
  expect(code).toContain("raise exception 'post-check: the held consumer correction is not held: %'")
})

test('Platform health shows recovery knowledge from the read-only admin read', () => {
  expect(code).toContain("if auth.uid() is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required'")
  expect(view).toContain("supabase.rpc('admin_ops_learning_v1')")
  expect(view).toContain('<RecoveryKnowledge/>')
  expect(view).toContain('data-ops-learning')
})
