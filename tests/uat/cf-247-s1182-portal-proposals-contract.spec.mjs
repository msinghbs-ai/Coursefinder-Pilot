// Guards: Platform Admin 26 Nov 2026 07:01 AEDT (s1182 Portal Release 2 backend) and the portal design decisions of 25 Nov 2026 10:37 and 10:45: proposals, append-only versions naming the editor with saved_after_other_edit, activity and preferences live in pipeline tables with row level security, reached only through public functions that check the person's own role (Viewer for activity and preferences, Counsellor for every proposal function); the student is a reference, a given name and a family initial only; archiving keeps who, when and why and never deletes; limits are portal settings; G3, locks and cron are checked.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261128235500_cf247_s1182_portal_proposals.sql', 'utf8')
const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const body = (name) => {
  const i = code.indexOf(`create or replace function public.${name}(`)
  expect(i, name).toBeGreaterThan(-1)
  return code.slice(i, code.indexOf('end $function$;', i))
}

test('s1182: four tables, RLS on, read policies by rank and own rows, no table privilege granted', () => {
  for (const t of ['portal_proposals', 'portal_proposal_versions', 'portal_activity', 'portal_user_prefs']) {
    expect(code).toContain(`create table pipeline.${t} (`)
    expect(code).toContain(`alter table pipeline.${t} enable row level security;`)
    expect(code).toMatch(new RegExp(`comment on table pipeline\\.${t} is '`))
  }
  expect(code).toContain('create policy portal_proposals_read on pipeline.portal_proposals for select to authenticated using (coalesce(security.current_role_rank(), 0) >= 2);')
  expect(code).toContain('create policy portal_activity_own on pipeline.portal_activity for select to authenticated using (user_id = auth.uid() and coalesce(security.current_role_rank(), 0) >= 1);')
  expect(code).toContain('revoke all on pipeline.portal_proposals, pipeline.portal_proposal_versions, pipeline.portal_activity, pipeline.portal_user_prefs from public, anon, authenticated;')
  expect(code).not.toMatch(/grant (select|insert|update|delete|all)[^;]*on pipeline\.portal_/i)
})

test('s1182: minimal student data, archive audit columns, append-only versions with the editor and the soft-lock flag', () => {
  const proposals = code.slice(code.indexOf('create table pipeline.portal_proposals ('), code.indexOf('comment on table pipeline.portal_proposals'))
  for (const c of ['student_ref', 'given_name', 'family_initial', 'last_editor_id', 'archived_at', 'archived_by', 'archived_reason']) expect(proposals).toContain(c)
  expect(proposals).not.toMatch(/email|phone|passport|birth|family_name|surname|address|source_country/i)
  const versions = code.slice(code.indexOf('create table pipeline.portal_proposal_versions ('), code.indexOf('comment on table pipeline.portal_proposal_versions'))
  expect(versions).toContain('edited_by              uuid        not null references auth.users (id)')
  expect(versions).toContain('saved_after_other_edit boolean     not null default false')
  expect(code).toContain('before update or delete on pipeline.portal_proposal_versions')
  expect(code).toContain("raise exception 'proposal versions are append only: a saved version is never changed or removed'")
})

test('s1182: role checks: Counsellor for every proposal function, Viewer for activity and preferences', () => {
  for (const f of ['portal_proposal_save_v1', 'portal_proposal_find_v1', 'portal_proposal_open_v1', 'portal_proposal_refresh_v1', 'portal_proposal_archive_v1'])
    expect(body(f)).toContain('security.portal_rank_v1(2);')
  for (const f of ['portal_activity_touch_v1', 'portal_activity_list_v1', 'portal_prefs_save_v1'])
    expect(body(f)).toMatch(/security\.portal_rank_v1\(1\);/)
  expect(body('portal_activity_touch_v1')).toContain("if v_kind = 'proposal' and v_rank < 2 then")
  expect(code).toContain('revoke all on function public.portal_proposal_save_v1(uuid, jsonb, jsonb, jsonb, text, text, integer, text, text, integer),')
  expect(code).toContain('public.portal_prefs_save_v1(text) to authenticated;')
})

test('s1182: save snapshots from live rows, warns after another edit, never blocks; refresh never writes; archive never deletes', () => {
  const save = body('portal_proposal_save_v1')
  expect(save).toContain('pipeline.portal_course_snapshot_v1(v_ids)')
  expect(save).toContain("v_conflict := (p_base_version is not null and p_base_version <> v_p.current_version)")
  expect(save).toContain("or (p_base_version is null and v_p.last_editor_id <> v_uid and v_p.updated_at > now() - make_interval(mins => v_lock));")
  expect(save).toContain("security.portal_setting_v1('proposal_max_courses')")
  expect(save).toContain("'saved_after_other_edit', v_conflict")
  const refresh = body('portal_proposal_refresh_v1')
  expect(refresh).toContain('stable security definer')
  expect(refresh).not.toMatch(/\b(insert|update|delete)\b/i)
  const archive = body('portal_proposal_archive_v1')
  expect(archive).toContain("set status = 'archived', archived_at = now(), archived_by = v_uid, archived_reason = v_reason")
  expect(archive).toContain("raise exception 'archiving needs a reason'")
  expect(body('portal_proposal_open_v1')).toContain("security.portal_setting_v1('edit_lock_minutes')")
  expect(body('portal_prefs_save_v1')).toContain("s.toolset_key = 'portal' and s.key = 'themes'")
})

test('s1182: settings, guards, housekeeping lines; nothing dropped, deleted, scheduled or sent to a model', () => {
  for (const k of ['proposal_max_courses', 'edit_lock_minutes', 'proposals_page_size', 'resume_items_shown', 'themes'])
    expect(code).toContain(`('portal', '${k}', `)
  expect(code).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(code).toContain('post-check: the number of active cron jobs changed')
  expect(code).toContain('post-check: manual locks changed')
  expect(code).toContain("post-check: a table or helper is reachable outside the portal functions")
  expect(sql).toMatch(/^-- Replaces: nothing/m)
  expect(sql).toMatch(/^-- Retires: nothing\./m)
  expect(code).not.toMatch(/^\s*(drop|truncate)\b/im)
  expect(code).not.toMatch(/^\s*delete\s+from/im)
  expect(code).not.toMatch(/cron\.schedule|openrouter|firecrawl|svc_pilot_submit_nonce/i)
})
