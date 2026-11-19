// Guards: CF-247 s802/s803 (Platform Admin 20 Nov 2026 05:52, chat S1-Build): Layer 4 inline Edit & Admit for University and Course descriptions;
// unedited text is machine_human_approved, edited text is human_input (checked, locked by hand unless declined, audited, review in six months)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { checkDescription, sentencesOf, bannedIn, isEdited } from '../../src/lib/description-check.js'

const MIG = fs.readFileSync('supabase/migrations/20261120100000_cf247_s802_s805_layer4_edit_admit_human_edit_audit.sql', 'utf8')
const INBOX = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8')
const EDIT = fs.readFileSync('src/DescriptionEditAdmit.jsx', 'utf8')
const fn = name => { const a = MIG.indexOf(`create or replace function ${name}(`); const b = MIG.indexOf('end $f$;', a); expect(a).toBeGreaterThan(-1); return MIG.slice(a, b) }

test('the internal approval takes the edited content and the lock choice, and splits provenance on the trimmed text', () => {
  const d = fn('security.layer4_description_decide_v1')
  expect(d).toContain('(p_item_id uuid, p_edited_content text, p_set_manual_lock boolean default true, p_reason text default null)')
  expect(d).toContain("v_edit text := nullif(btrim(coalesce(p_edited_content, '')), '')")
  expect(d).toContain("if v_edit is null or v_edit = v_orig then")
  expect(d).toContain("return public.layer4_review_decide(p_item_id, 'approve', p_reason, null);")
  expect(d).toContain("return public.layer4_review_decide(p_item_id, 'edit_and_approve', p_reason,")
  expect(d).toContain("'set_manual_lock', coalesce(p_set_manual_lock, true)")
  expect(MIG).toContain('revoke all on function security.layer4_description_decide_v1(uuid, text, boolean, text) from public, anon, authenticated;')
})

test('edited text is admitted as human input: checked, guarded, locked unless declined, audited with a review in six months', () => {
  const h = fn('security.layer4_description_human_admit_v1')
  expect(h).toContain("rr.rank >= 4")
  expect(h).toContain('v_check := security.description_text_check_v1(v_entity, v_text);')
  expect(h).toContain("the description is already locked by hand")
  expect(h).toContain("the description changed since this was proposed")
  expect(h).toContain("perform set_config('cf.manual_edit', 'on', true);")
  expect(h).toContain("insert into pipeline.manual_locks (entity, entity_id, field, mode, set_by) values (v_entity, i.entity_id, 'description', 'value', p_actor)")
  expect(h).toContain("v_lock := coalesce((p_value->>'set_manual_lock')::boolean, true);")
  expect(h).toContain("'human_input', true,")
  const r = fn('security.human_edit_audit_record_v1')
  expect(r).toContain("make_interval(months => security.pipeline_num_v1('governance.human_edit_review_months', 6)::int)")
  expect(r).toContain("case when p_was_edited then 'pending_ack' else 'not_applicable' end")
})

test('the "approved as read, never edited" refusal is replaced in both apply functions; approval as read records machine_human_approved', () => {
  expect(MIG).toContain("-- Replaces: the \"approved as read, never edited\" refusal in security.layer4_provider_description_apply_impl and security.layer4_course_description_apply_v1.")
  expect(MIG).toContain("select pg_temp.cf_edit_def('security.layer4_provider_description_apply_impl(uuid,uuid,jsonb,text)'::regprocedure, '97685b737007410288297dea9d650d2a',")
  expect(MIG).toContain("select pg_temp.cf_edit_def('security.layer4_course_description_apply_v1(uuid,uuid,jsonb,text)'::regprocedure, 'ba97236f3010e248bac44a0a7c09611a',")
  expect(MIG.match(/if p_value is distinct from i\.proposed_value then return security\.layer4_description_human_admit_v1\(p_actor, i\.id, p_value, p_reason\); end if;/g)).toHaveLength(2)
  expect(MIG.match(/'machine_human_approved', false, v_text, v_text, false, p_reason, null\);  -- s802/g)).toHaveLength(2)
  expect(MIG).toContain("if md5(v_def) <> p_md5 then raise exception 'pre-check:")
})

test('the Inbox offers Save Edit & Admit at rank 4 through public.admin_layer4_inbox; no public function is added', () => {
  expect(MIG).toContain("select pg_temp.cf_edit_def('public.admin_layer4_inbox(text,jsonb)'::regprocedure, '3dd1d45d43332dd60a274c9996238806',")
  expect(MIG).toContain("jsonb_build_object('key', 'edit_approve', 'label', 'Save Edit & Admit', 'input', 'text', 'editor', true, 'rank', 4,")
  expect(MIG).toContain("elsif v_kind = 'provider_description' and v_choice = 'edit_approve' then")
  expect(MIG).toContain("v_r := security.layer4_description_decide_v1(v_ref::uuid, p_args->>'value', coalesce((p_args->>'set_manual_lock')::boolean, true), v_reason);")
  expect(MIG).not.toMatch(/create (or replace )?(function|view|table) (public|api)\./)
  expect(MIG).toContain('-- G3: no consumer object changes')
})

test('the card: Edit & Approve opens the editor with the quotes, the source link, live counts and the two buttons', () => {
  expect(INBOX).toContain("import DescriptionEditAdmit,{HeldUniversities}from'./DescriptionEditAdmit'")
  expect(INBOX).toContain("cdChoices(choices.filter(c=>c.key!=='edit_approve'),isCourseDescription(d))")
  expect(INBOX).toContain('data-l4-choice="edit_approve">Edit &amp; Approve</button>')
  expect(INBOX).toContain('<DescriptionEditAdmit it={it} d={d} isCourse={isCourseDescription(d)} rank={rank}')
  for (const s of ['data-dea-text', 'data-dea-quotes', 'data-dea-source', 'data-dea-checks', 'data-dea-banned', 'data-dea-lock', 'Save Edit & Admit', 'Approve As-Is'])
    expect(EDIT).toContain(s)
  expect(EDIT).toContain("rpc('decide',{kind:it.kind,ref:it.ref,choice:'edit_approve',value:asIs?original:text.trim(),set_manual_lock:lock,reason:reason.trim()})")
  expect(EDIT).toContain("disabled={low||!!busy||!edited||!c?.ok||!reasonOk}")
  expect(EDIT).toContain("disabled={low||!!busy||held||edited||!reasonOk}")
})

test('held universities are opened for writing from their stored page (rank 4), never with machine text', () => {
  const a = fn('security.human_edit_admin_v1')
  expect(a).toContain("elsif p_action = 'description_open_held' then")
  expect(a).toContain("if v_read.id is null or v_read.state <> 'held' then raise exception 'this university has no held reading to write from'")
  expect(a).toContain("jsonb_build_object('description', '', 'sentences', '[]'::jsonb, 'source_url', v_read.source_url")
  expect(EDIT).toContain("rpc('description_open_held',{provider_id:id})")
  expect(INBOX).toContain("view==='kind'&&kind==='provider_description'&&<HeldUniversities")
})

test('the live checks follow the readers\' own limits and word lists', () => {
  const rules = { min_chars: 20, max_chars: 120, min_sentences: 1, max_sentences: 2, words: ['world-class', 'leading'] }
  expect(sentencesOf('One. Two! Three?')).toHaveLength(3)
  expect(bannedIn('A world-class place, misleading words.', rules.words)).toEqual(['world-class'])
  const ok = checkDescription('The university teaches law and nursing in Sydney.', rules)
  expect(ok.ok).toBe(true)
  expect(ok.words).toBe(8)
  const bad = checkDescription('A leading place. Another one. A third one here.', rules)
  expect(bad.ok).toBe(false)
  expect(bad.problems.join('; ')).toContain('at most 2 sentences (has 3)')
  expect(bad.banned).toEqual(['leading'])
  expect(isEdited('  Same text. ', 'Same text.')).toBe(false)
  expect(isEdited('same text.', 'Same text.')).toBe(true)
})

test('the migration proves it on live items in a rolled-back sub-block and keeps nothing', () => {
  for (const s of ["course edit: admitted, locked, audited (human_input)", "course approve as read: machine_human_approved", "held university opened and written by hand: admitted, locked", "raise exception 'cf-s802-undo';", "post-check: a too-short edit was admitted", "post-check: the audit is not empty at creation"])
    expect(MIG).toContain(s)
})
