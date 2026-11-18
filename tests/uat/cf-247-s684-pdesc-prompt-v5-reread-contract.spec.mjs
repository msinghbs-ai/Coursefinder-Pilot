// Guards: University description prompt version 5 and re-read pdesc-reread-p5 (Platform Admin 18 Nov 2026 17:52 item 2): the active provider-description prompt asks for two to three sentences, the first beginning with the provider's full name, and leaves out the words the wording check refuses most often; the waiting descriptions are sent back to the reader once by superseding their Layer 4 items and queuing a new read, with nothing deleted; the validation, the machine gate, the word lists and the admission are not changed.
// CF-247 S684. Migration 20261118213000_cf247_held_scholarship_settle_pdesc_prompt_v5. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const raw = fs.readFileSync('supabase/migrations/20261118213000_cf247_held_scholarship_settle_pdesc_prompt_v5.sql', 'utf8')
const code = raw.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = (name, end = '$function$;') => { const i = code.indexOf(`create or replace function ${name}(`); return code.slice(i, code.indexOf(end, i)) }

test('version 5 is built from the active version 4 and names the provider at the start of the first of two to three sentences', () => {
  expect(code).toContain("select system_prompt into v4 from pipeline.provider_description_prompts where version = 4 and status = 'active';")
  expect(code).toContain("raise exception 'prompt version 4 is not active (the Platform Admin saved another); version 5 not added and nothing applied';")
  expect(code).toContain("v5 := replace(v4, l1, 'Write 2 to 3 sentences (about 40 to 90 words)');")
  expect(code).toContain("The first sentence must begin with the provider''s full name exactly as given and say what kind of institution it is;")
  expect(code).toContain('- Never use these words, and leave out a fact that cannot be said without one: accredited, accreditation, excellence,')
  expect(code).toContain("update pipeline.provider_description_prompts set status = 'retired' where version = 4;")
  expect(code).toContain("raise exception 'post-check: prompt version 5 is not the one active prompt';")
})

test('waiting descriptions are superseded, never rejected or deleted, and each provider gets one queued read', () => {
  expect(code).toContain("where i.status = 'pending' and i.entity_type = 'provider' and i.field_code = 'provider_description'")
  expect(code).toContain("and r.prompt_version is distinct from 'provider-description-p5');")
  expect(code).toContain("set status = 'superseded', decided_at = now(),")
  expect(code).toContain("where not exists (select 1 from pipeline.provider_description_reads r where r.provider_id = c.provider_id and r.state in ('queued', 'reading', 'proposed'));")
  expect(code).toContain("l.field in ('description', 'p_description', 'all'))")
  expect(code).not.toMatch(/status = 'rejected'|on_demand/)
  expect(code).toContain("raise exception 'post-check: a description sent back has no queued read or is still pending';")
})

test('no check, word list, gate or admission is changed and no description is written', () => {
  expect(code).not.toMatch(/function security\.(provider_description_validate_v1|provider_description_machine_gate_v1|provider_description_machine_admit_v1|pdesc_machine_text_check|pdesc_name_forms_v1)/)
  expect(code).not.toMatch(/'pdesc\.(machine_refused_words|min_sentences|max_sentences|claim_words)'|update catalogue\.providers|insert into catalogue\./)
})
