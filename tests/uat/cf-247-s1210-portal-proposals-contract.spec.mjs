// Guards: Platform Admin 26 Nov 2026 07:01 and 07:37 AEDT (s1210 Portal Release 2 backend, matching the live screens s1200 to s1202) and the decisions of 26 Nov 07:30 (contract functions on pipeline tables; academic facts allowed, identity minimal; a stale save writes nothing unless forced; status ready): public.portal_proposal_list/get/save/refresh_v1 take one p_args jsonb and answer the Release 2 contract shapes; proposals, append-only versions (last_editor_id, saved_after_other_edit), activity and preferences live in pipeline tables with row level security and no table privilege; Counsellor for every portal_proposal function, Viewer for activity and preferences, anon nothing; snapshots are built on the server and kept until a refresh is accepted; limits, defaults and the soft-lock window are portal settings; archive keeps who, when and why with expires_at retention; G3, locks and cron are checked.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261129003000_cf247_s1210_portal_proposals.sql', 'utf8')
const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const api = fs.readFileSync('portal/src/lib/proposalApi.js', 'utf8')
const body = (name) => {
  const i = code.indexOf(`create or replace function public.${name}(`)
  expect(i, name).toBeGreaterThan(-1)
  return code.slice(i, code.indexOf('end $function$;', i))
}

test('s1210: every function the live screens call exists with one p_args jsonb', () => {
  for (const name of [...api.matchAll(/call\('(portal_proposal_[a-z_]+_v1)'/g)].map((m) => m[1]).concat(['portal_proposal_list_v1'])) {
    expect(code).toContain(`create or replace function public.${name}(p_args jsonb default '{}'::jsonb)`)
  }
  for (const name of ['portal_proposal_archive_v1', 'portal_activity_touch_v1', 'portal_activity_list_v1', 'portal_prefs_save_v1'])
    expect(code).toContain(`create or replace function public.${name}(p_args jsonb default '{}'::jsonb)`)
})

test('s1210: reply shapes follow the Release 2 contract', () => {
  const list = body('portal_proposal_list_v1')
  for (const k of ["'items'", "'total'", "'page'", "'page_size'", "'facets'", "'counts'", "'needs_refresh_count'", "'needs_refresh'", "'change_note'", "'updated_by_name'", "'updated_by_me'", "'details_checked_at'", "'last_pdf_version'", "'source_country_name'"]) expect(list).toContain(k)
  const get = body('portal_proposal_get_v1')
  for (const k of ["'defaults'", "'limits'", "'courses_max'", "'message_max_chars'", "'note_max_chars'", "'why_max_chars'", "'others_recent'", "'opened_at'", "'soft_lock_minutes'", "'counsellor'"]) expect(get).toContain(k)
  const save = body('portal_proposal_save_v1')
  expect(save).toContain("return jsonb_build_object('status', 'saved_after_other_edit', 'current_version', v_p.current_version,")
  expect(save).toContain("'by_name', pipeline.portal_user_label_v1(v_p.last_editor_id), 'saved_at', v_p.updated_at,")
  expect(save).toContain("return jsonb_build_object('status', 'saved', 'id', v_p.id, 'version', v_ver,")
  expect(save).toContain("if v_base is not null and v_base <> v_p.current_version then\n      if not v_force then")
  const refresh = body('portal_proposal_refresh_v1')
  expect(refresh).toContain("return jsonb_build_object('checked_at', now(), 'built_at', v_v.edited_at, 'changes',")
  expect(refresh).toContain("return jsonb_build_object('status', 'kept', 'checked_at', now());")
  expect(refresh).toContain("'live_snapshots', true")
  expect(code).toContain("jsonb_build_object('course_id', cid, 'course_title', ttl, 'provider_name',")
  expect(code).toContain("'field', f.field, 'label', f.label, 'from_text',")
})

test('s1210: tables, row level security, minimal identity, statuses, retention, append-only versions', () => {
  for (const t of ['portal_proposals', 'portal_proposal_versions', 'portal_activity', 'portal_user_prefs']) {
    expect(code).toContain(`create table pipeline.${t} (`)
    expect(code).toContain(`alter table pipeline.${t} enable row level security;`)
    expect(code).toMatch(new RegExp(`comment on table pipeline\\.${t} is '`))
  }
  expect(code).toContain('revoke all on pipeline.portal_proposals, pipeline.portal_proposal_versions, pipeline.portal_activity, pipeline.portal_user_prefs from public, anon, authenticated;')
  expect(code).not.toMatch(/grant (select|insert|update|delete|all)[^;]*on pipeline\.portal_/i)
  const p = code.slice(code.indexOf('create table pipeline.portal_proposals ('), code.indexOf('comment on table pipeline.portal_proposals'))
  for (const c of ['student_ref', 'given_name', 'family_initial', 'archived_at', 'archived_by', 'archived_reason', 'expires_at', 'last_editor_id']) expect(p).toContain(c)
  expect(p).not.toMatch(/email|phone|passport|birth|family_name|surname|address/i)
  expect(p).toContain("check (status in ('draft', 'ready', 'sent', 'accepted', 'archived'))")
  const v = code.slice(code.indexOf('create table pipeline.portal_proposal_versions ('), code.indexOf('comment on table pipeline.portal_proposal_versions'))
  expect(v).toContain('last_editor_id         uuid        not null references auth.users (id)')
  expect(v).toContain('saved_after_other_edit boolean     not null default false')
  expect(code).toContain('before update or delete on pipeline.portal_proposal_versions')
  expect(body('portal_proposal_save_v1')).toContain("expires_at = now() + make_interval(months => v_keep)")
})

test('s1210: role guards and grants: Counsellor for proposals, Viewer for activity and preferences, anon none', () => {
  for (const f of ['portal_proposal_list_v1', 'portal_proposal_get_v1', 'portal_proposal_save_v1', 'portal_proposal_refresh_v1', 'portal_proposal_archive_v1'])
    expect(body(f)).toContain('perform security.portal_rank_v1(2);')
  for (const f of ['portal_activity_touch_v1', 'portal_activity_list_v1', 'portal_prefs_save_v1']) expect(body(f)).toMatch(/security\.portal_rank_v1\(1\);/)
  expect(code).toMatch(/revoke all on function public\.portal_proposal_list_v1\(jsonb\)[\s\S]*?from public, anon;/)
  expect(code).toMatch(/grant execute on function public\.portal_proposal_list_v1\(jsonb\)[\s\S]*?to authenticated;/)
})

test('s1210: snapshots kept until accepted; limits and defaults are settings; nothing dropped, deleted, scheduled or sent to a model', () => {
  const save = body('portal_proposal_save_v1')
  expect(save).toContain("case when not v_live and v_old ? (c->>'course_id') then v_old->(c->>'course_id') else q.s end")
  for (const k of ['proposal_max_courses', 'proposal_message_max_chars', 'proposal_note_max_chars', 'proposal_why_max_chars', 'edit_lock_minutes', 'proposals_page_size',
                   'proposal_retention_months', 'resume_items_shown', 'themes', 'proposal_default_steps', 'proposal_default_documents'])
    expect(code).toContain(`('portal', '${k}', `)
  expect(code).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(code).toContain('post-check: the number of active cron jobs changed')
  expect(code).toContain('post-check: manual locks changed')
  expect(sql).toMatch(/^-- Replaces: nothing/m)
  expect(sql).toMatch(/^-- Retires: nothing\./m)
  expect(code).not.toMatch(/^\s*(drop|truncate)\s+(table|function|schema)/im)
  expect(code).not.toMatch(/^\s*delete\s+from/im)
  expect(code).not.toMatch(/cron\.schedule|openrouter|firecrawl|svc_pilot_submit_nonce/i)
})
