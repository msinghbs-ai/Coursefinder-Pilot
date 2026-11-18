// Guards: Held scholarship settlement rule l4-held-sch-settle-v1 (Platform Admin 18 Nov 2026 17:52 item 1): a held scholarship page is admitted by rule only when its AI re-check says international with the audience and value sentences found on the page, the first reading agrees, and the page is on the provider's own https host with no refused address word; it is refused by rule only when the re-check found a domestic-only sentence the first reading does not contradict; audience not stated, value unclear, not settled and disagreeing readings stay held; both decisions go through the existing decision under the system automation account with the sentences in the note.
// CF-247 S683. Migration 20261118213000_cf247_held_scholarship_settle_pdesc_prompt_v5. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const raw = fs.readFileSync('supabase/migrations/20261118213000_cf247_held_scholarship_settle_pdesc_prompt_v5.sql', 'utf8')
const code = raw.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = (name, end = '$function$;') => { const i = code.indexOf(`create or replace function ${name}(`); return code.slice(i, code.indexOf(end, i)) }

const f = fn('security.scholarship_recheck_queue_rule_v1')

test('admit needs a clear re-check, both sentences on the page, the first reading\'s agreement and the provider\'s own https page', () => {
  expect(f).toContain("when r.recheck->>'recommendation' = 'international_check_and_publish'")
  expect(f).toContain("and r.recheck->>'audience_proven' = 'true' and r.recheck->>'value_proven' = 'true'")
  expect(f).toContain("and r.recheck->>'audience' in ('international', 'both') and e.answer->>'audience' in ('international', 'both')")
  expect(f).toContain("and r.recheck->>'audience_quote' ~* '\\minternational\\M'")
  expect(f).toContain("and r.url ~* '^https://' and security.provider_page_host_v1(r.provider_id, r.url) = 'own'")
  expect(f).toContain("security.pipeline_list_v1('scholarship.settle_refused_path_words', '[]'::jsonb)")
  expect(f).toContain('and c.admitted_scholarship_id is not null)')
})

test('refuse needs a domestic-only sentence found on the page that the first reading does not contradict; everything else is held', () => {
  expect(f).toContain("when r.recheck->>'recommendation' = 'not_for_international'")
  expect(f).toContain("and r.recheck->>'audience_proven' = 'true' and r.recheck->>'audience' = 'domestic'")
  expect(f).toContain("and coalesce(e.answer->>'audience', '') not in ('international', 'both')")
  expect(f).toContain("else 'hold' end verdict")
  expect(f).toContain("and r.recheck->>'recommendation' in ('international_check_and_publish', 'not_for_international')")
  expect(f).toContain("if w.verdict = 'hold' then v_held := v_held + 1; continue; end if;")
  expect(f).not.toMatch(/'audience_not_stated'|'international_value_unclear'|'unsettled'/)
})

test('only the existing decision, under the system automation account, with the sentences in the note and the audit row marked as a rule', () => {
  expect(f).toContain('v_res := security.scholarship_ai_review_apply_v1(w.id, w.verdict, w.extraction_id,')
  expect(f).toContain("v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150';")
  expect(f).toContain("'[rule l4-held-sch-settle-v1] %s Audience sentence on the page: \"%s\"%s Approved by Platform Admin 18 Nov 2026 17:52'")
  expect(f).toContain("jsonb_build_object('by_person', false, 'by_rule', 'l4-held-sch-settle-v1')")
  expect(f).not.toMatch(/insert into scholarship\.|update scholarship\.|publication_status|scholarship_publication_holds/)
  expect(f).toContain("if security.pipeline_num_v1('scholarship.held_settle_rule_on', 0) >= 1 then")
})

test('the re-check queue step is kept, the live text is checked first, no new function or job, nothing dropped', () => {
  expect(f).toContain("where r.status = 'pending' and r.recheck is null and nullif(btrim(coalesce(r.storage_path, '')), '') is not null")
  expect(code).toContain("<> '613efb697381219f1ab49d194559080f'")
  expect((code.match(/create or replace function /g) || []).length).toBe(1)
  expect(code).not.toMatch(/cron\.schedule|create table|alter table|add column/i)
  expect(code).toContain("raise exception 'post-check: the rule admitted a page without a clear re-check';")
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|schema|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
})
