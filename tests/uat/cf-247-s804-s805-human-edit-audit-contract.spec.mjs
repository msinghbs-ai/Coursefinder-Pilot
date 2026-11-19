// Guards: CF-247 s804/s805 (Platform Admin 20 Nov 2026 05:52, chat S1-Build): pipeline.human_edit_audit; Data & Governance › Human Edits &
// Periodic Audit (My Human Edits, All Human Edits for the Platform Admin, Unacknowledged and Due badges) and its four governed bulk actions
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES, SECTIONS } from '../../src/nav-map.js'

const MIG = fs.readFileSync('supabase/migrations/20261120101000_cf247_s802_s805_layer4_edit_admit_human_edit_audit.sql', 'utf8')
const PAGE = fs.readFileSync('src/HumanEditsAudit.jsx', 'utf8')
const SHELL = fs.readFileSync('src/mature-main.jsx', 'utf8')
const ADMIN = (() => { const a = MIG.indexOf('create or replace function security.human_edit_admin_v1('); return MIG.slice(a, MIG.indexOf('end $f$;', a)) })()

test('pipeline.human_edit_audit holds every field the directive names, internal only', () => {
  const t = MIG.slice(MIG.indexOf('create table if not exists pipeline.human_edit_audit ('), MIG.indexOf('comment on table pipeline.human_edit_audit'))
  for (const c of ['entity_type', 'entity_id', 'field_name', 'country_code', 'provider_type', 'admission_source', 'was_edited', 'original_candidate_text', 'edited_text', 'final_approved_text', 'edited_by', 'edited_at', 'admin_acknowledged_by', 'admin_acknowledged_at', 'next_review_due_at', 'recheck_status', 'revision', 'supersedes_id'])
    expect(t).toMatch(new RegExp(`\\n  ${c} `))
  expect(t).toContain("check (admission_source in ('machine_human_approved', 'human_input'))")
  expect(MIG).toContain('alter table pipeline.human_edit_audit enable row level security;')
  expect(MIG).toContain('revoke all on pipeline.human_edit_audit from public, anon, authenticated;')
})

test('My Human Edits is the reviewer\'s own (rank 4); All Human Edits is the Platform Admin\'s (rank 6); the server checks each row', () => {
  expect(ADMIN).toContain("if v_scope = 'all' and v_rank < 6 then raise exception 'All Human Edits is for the Platform Admin'")
  expect(ADMIN).toContain("and (v_scope = 'all' or a.edited_by = v_uid)")
  expect(ADMIN).toContain("you can act only on your own edits; the Platform Admin acts on all")
  expect(ADMIN).toContain("when 'due' then b.next_review_due_at <= now()")
  expect(ADMIN).toContain("'unacknowledged', (select count(*) from base where admin_acknowledged_at is null")
  expect(PAGES.governance.tabs).toEqual([{ key: 'mine', label: 'My Human Edits', min: 4 }, { key: 'all', label: 'All Human Edits (Admin Governance)', min: 6 }])
  expect(SECTIONS.find(s => s.label === 'Data & Governance').pages).toEqual(['governance'])
  expect(SHELL).toContain("case'governance':return <HumanEditsAudit key={tab} tab={tab} rank={rank} onError={err}/>")
  for (const s of ['data-he-badge="unacknowledged"', 'data-he-badge="due"', 'Due for 6-month re-review', 'Unacknowledged'])
    expect(PAGE).toContain(s)
})

test('the four governed actions: acknowledge resets six months, re-verify reads nothing and overwrites nothing, edit makes a revision, release clears the lock', () => {
  expect(ADMIN).toContain("if p_action = 'human_edits_ack' then")
  expect(ADMIN).toContain("next_review_due_at = now() + make_interval(months => security.pipeline_num_v1('governance.human_edit_review_months', 6)::int)")
  const re = ADMIN.slice(ADMIN.indexOf("elsif p_action = 'human_edits_recheck' then"), ADMIN.indexOf("elsif p_action = 'human_edits_edit' then"))
  expect(re).toContain('no reading, no AI, no Firecrawl; nothing is overwritten')
  expect(re).not.toMatch(/update catalogue\.|manual_locks|net\.http|firecrawl_|openrouter/i)
  expect(re).toContain("update pipeline.human_edit_audit set recheck_status = 'rechecked'")
  const ed = ADMIN.slice(ADMIN.indexOf("elsif p_action = 'human_edits_edit' then"), ADMIN.indexOf("elsif p_action = 'human_edits_release' then"))
  expect(ed).toContain("if cardinality(v_ids) <> 1 then raise exception 'edit one description at a time'")
  expect(ed).toContain("update pipeline.human_edit_audit set recheck_status = 'superseded' where id = rw.id;")
  expect(ed).toContain("'human_input', true, rw.edited_text, v_text, true, p_args->>'reason', rw.id)")
  const rl = ADMIN.slice(ADMIN.indexOf("elsif p_action = 'human_edits_release' then"), ADMIN.indexOf("elsif p_action = 'human_edits_accept_machine' then"))
  expect(rl).toContain("with d as (delete from pipeline.manual_locks where entity = rw.entity_type and entity_id = rw.entity_id and field = 'description' returning 1)")
  expect(ADMIN).toContain("if p_action in ('human_edits_release', 'human_edits_accept_machine') and v_rank < 6 then raise exception 'releasing a lock is for the Platform Admin'")
  expect(ADMIN).toContain("insert into pipeline.admin_control_events (area, action, target, detail, actor)")
})

test('the page: checkbox multi-select, bulk Acknowledge, Re-Verify and Release, single Edit & Re-Lock, side-by-side diff', () => {
  for (const s of ['data-he-all', 'data-he-tick', 'data-he-act="ack"', 'data-he-act="recheck"', 'data-he-act="release"', 'data-he-one="edit"', 'data-he-fresh', 'data-he-current', 'data-he-original', 'Acknowledge & Keep Lock', 'Re-Verify by Machine', 'Release Lock to Machine', 'Edit &amp; Re-Lock', 'Fresh machine candidate', 'Current human text'])
    expect(PAGE).toContain(s)
  expect(PAGE).toContain("{admin&&<Button compact disabled={!sel.length||!!busy} onClick={()=>setConfirm('release')} data-he-act=\"release\">")
  expect(PAGE).toContain("act('human_edits_edit',[x.id],{text:text.trim(),reason:reason.trim()})")
})
