// Guards: Platform Admin 18 Nov 2026 07:39 (Destination data › Localities & postcodes › Bulk Approve Drafts): one action approves every clean draft locality of a dataset edition; it is the Platform Admin's, needs one reason, changes draft localities only, leaves a draft without attribution, and is recorded once in the control log.
// Behaviour is proven on the real destination schema, on isolated PostgreSQL, by tests/fixtures/destination-bulk-approve/run.sh (workflow destination-bulk-approve-test); these checks keep the rules in the migration and the screen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { draftEditions } from '../../src/lib/destination-drafts.js'

const read = (p) => fs.readFileSync(p, 'utf8')
const m = read('supabase/migrations/20261118090707_cf247_destination_localities_bulk_approve.sql')
const c = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const screen = read('src/DestinationData.jsx')

test('the migration adds one function beside the single approval and changes no existing object', () => {
  expect(m).toMatch(/^-- Replaces: nothing$/m); expect(m).toMatch(/^-- Retires: nothing$/m)
  for (const l of m.split('\n')) expect(l).not.toMatch(/^(drop|delete|truncate|update|alter|insert)\b/i)
  expect(c.match(/create or replace function /g).length).toBe(1)
  expect(c).toContain("create or replace function public.admin_destination_localities_bulk_approve(p_dataset_edition text, p_reason text) returns jsonb\nlanguage plpgsql security definer set search_path = ''")
  expect(c).toContain('revoke all on function public.admin_destination_localities_bulk_approve(text, text) from public, anon;')
})

test('the Platform Admin, one reason, clean drafts of one edition only, one control event', () => {
  expect(c).toContain("if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) is needed to approve or withdraw destination data'")
  expect(c).toContain("if v_reason is null then raise exception 'a reason is required' using errcode = '22023'; end if;")
  expect(c).toContain("where l.dataset_edition = v_ed and l.status = 'draft' and nullif(btrim(l.attribution_text), '') is not null and nullif(btrim(l.name), '') is not null")
  // the only tables written: the localities and the control log; no figure, rule or edition
  expect([...c.matchAll(/\b(?:update|insert into) (destination\.[a-z_]+|pipeline\.[a-z_]+)/g)].map((x) => x[1])).toEqual(['destination.localities', 'pipeline.admin_control_events'])
  expect(c).toContain("values ('destination', 'localities_bulk_approve', v_ed,")
  expect(c).toContain("set status = 'approved', status_reason = v_reason, status_changed_by = v_uid, status_changed_at = now(), updated_at = now()")
})

test('the screen counts what is ready by edition, with the server\'s own rule', () => {
  const rows = [{ status: 'draft', dataset_edition: 'ABS 2024-25', name: 'Geelong', attribution_text: 'Source: ABS' }, { status: 'draft', dataset_edition: 'ABS 2024-25', name: 'Ballarat', attribution_text: '  ' },
    { status: 'draft', dataset_edition: 'ABS 2024-25', name: 'Bendigo', attribution_text: 'Source: ABS' }, { status: 'approved', dataset_edition: 'ABS 2024-25', name: 'Melbourne', attribution_text: 'Source: ABS' },
    { status: 'in_review', dataset_edition: 'ABS 2024-25', name: 'Cairns', attribution_text: 'Source: ABS' }, { status: 'draft', dataset_edition: 'A earlier', name: 'Hobart', attribution_text: 'Source: ABS' }, { status: 'draft', dataset_edition: '', name: 'No edition', attribution_text: 'x' }]
  expect(draftEditions(rows)).toEqual([{ edition: 'A earlier', ready: 1, left: 0 }, { edition: 'ABS 2024-25', ready: 2, left: 1 }])
  expect(draftEditions([{ status: 'approved', dataset_edition: 'E' }])).toEqual([])
})

test('the screen: the button is the Platform Admin\'s, asks one reason and calls the bulk function; the result says what was approved and what was left', () => {
  expect(screen).toContain('<BulkApprove rows={loc.rows||[]} rank={rank} run={run}/>')
  expect(screen).toContain('<Act label="Bulk Approve Drafts" need={6} rank={rank} primary data="locality-bulk-approve"')
  expect(screen).toContain("if(r)run('admin_destination_localities_bulk_approve',{p_dataset_edition:e.edition,p_reason:r})")
  expect(screen).toContain('const ask=t=>{const r=window.prompt(`${t}\\n\\nReason (kept with the decision):`);return r&&r.trim().length>=4?r.trim():null}')
  expect(screen).toContain("data?.approved!=null&&data?.dataset_edition?`Approved ${data.approved} of ${data.drafts} draft localities of ${data.dataset_edition}")
  // the single Approve stays as it was
  expect(screen).toContain("if(r)run('admin_destination_set_status',{p_kind:'locality',p_id:l.id,p_status:'approved',p_reason:r})")
  expect(read('src/destination-data.css')).not.toMatch(/#[0-9a-fA-F]{3,8}\b/)
})
