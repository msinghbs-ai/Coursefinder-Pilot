// Guards: Platform Admin 18 Nov 2026 07:39 and 10:05 (Destination data › Bulk Approve Drafts on Localities & postcodes and on City metrics & costs): one action approves every clean draft locality, or every clean draft city figure, of a dataset edition; it is the Platform Admin's, needs one reason, changes drafts of its own kind only, leaves a draft without attribution, and is recorded once in the control log. The ILEP draft's note no longer says its scheme is to be registered.
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
  expect(screen).toContain('<Act label="Bulk Approve Drafts" need={6} rank={rank} primary data={w.data} onRun=')
  expect(screen).toContain("fn:'admin_destination_localities_bulk_approve',data:'locality-bulk-approve'")
  expect(screen).toContain('if(r)run(w.fn,{p_dataset_edition:e.edition,p_reason:r})')
  expect(screen).toContain('const ask=t=>{const r=window.prompt(`${t}\\n\\nReason (kept with the decision):`);return r&&r.trim().length>=4?r.trim():null}')
  expect(screen).toContain("data?.approved!=null&&data?.dataset_edition?`Approved ${data.approved} of ${data.drafts} draft ${data.kind==='figures'?'figures':'localities'} of ${data.dataset_edition}")
  // the single Approve stays as it was
  expect(screen).toContain("if(r)run('admin_destination_set_status',{p_kind:'locality',p_id:l.id,p_status:'approved',p_reason:r})")
  expect(read('src/destination-data.css')).not.toMatch(/#[0-9a-fA-F]{3,8}\b/)
})

// City figures and the ILEP note (Platform Admin 18 Nov 2026 10:05, migration 20261118110707)
const m2 = read('supabase/migrations/20261118110707_cf247_destination_figures_bulk_approve.sql')
const c2 = m2.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('figures: one more function with the same rules; it changes draft figures and the control log only', () => {
  expect(m2).toMatch(/^-- Replaces: nothing$/m); expect(m2).toMatch(/^-- Retires: nothing$/m)
  for (const l of m2.split('\n')) expect(l).not.toMatch(/^(drop|delete|truncate|alter)\b/i)
  expect(c2.match(/create or replace function /g).length).toBe(1)
  expect(c2).toContain("create or replace function public.admin_destination_figures_bulk_approve(p_dataset_edition text, p_reason text) returns jsonb\nlanguage plpgsql security definer set search_path = ''")
  expect(c2).toContain("if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) is needed to approve or withdraw destination data'")
  expect(c2).toContain("if v_reason is null then raise exception 'a reason is required' using errcode = '22023'; end if;")
  expect(c2).toContain("where m.dataset_edition = v_ed and m.status = 'draft' and nullif(btrim(m.attribution_text), '') is not null and m.numeric_value is not null")
  expect(c2).toContain("values ('destination', 'figures_bulk_approve', v_ed,")
  expect(c2).toContain('revoke all on function public.admin_destination_figures_bulk_approve(text, text) from public, anon;')
  const body = c2.slice(c2.indexOf('create or replace function'), c2.indexOf('comment on function'))
  expect([...body.matchAll(/\b(?:update|insert into) (destination\.[a-z_]+|pipeline\.[a-z_]+)/g)].map((x) => x[1])).toEqual(['destination.locality_metrics', 'pipeline.admin_control_events'])
})

test('the ILEP note is rewritten only while it is still the text the earlier migration wrote', () => {
  const note = c2.match(/jsonb_build_object\('notes', '((?:[^']|'')+)'\)/)[1]
  expect(note).not.toContain('ie_ilep'); expect(note).toContain('TrustEd Ireland'); expect(note).toMatch(/^Wave 2 draft, pre-staged 17 Nov 2026\. DEPRECATING SOURCE/); expect(note.length).toBeLessThanOrEqual(600)
  expect(c2).toContain("and i.payload->>'notes' like 'Wave 2 draft, pre-staged 17 Nov 2026. DEPRECATING SOURCE (Platform Admin 18 Nov 2026):%Scheme ie_ilep is to be registered in ref.registration_schemes (with S2-Build) before step 1 can finish.';")
  // the only other write of the migration
  expect([...c2.matchAll(/^(?:update|insert into) ([a-z0-9_.]+)/gm)].map((x) => x[1])).toEqual(['pipeline.layer1_source_inductions'])
})

test('figures on the screen: the same button on City metrics & costs, counted with the server\'s rule', () => {
  expect(screen).toContain('<BulkApprove rows={m.rows||[]} rank={rank} run={run} kind="figure"/>')
  expect(screen).toContain("fn:'admin_destination_figures_bulk_approve',data:'metric-bulk-approve'")
  const rows = [{ status: 'draft', dataset_edition: 'ABS 2024-25', numeric_value: 5, attribution_text: 'Source: ABS' }, { status: 'draft', dataset_edition: 'ABS 2024-25', numeric_value: 0, attribution_text: 'Source: ABS' },
    { status: 'draft', dataset_edition: 'ABS 2024-25', numeric_value: 7, attribution_text: '' }, { status: 'approved', dataset_edition: 'ABS 2024-25', numeric_value: 7, attribution_text: 'Source: ABS' }]
  expect(draftEditions(rows, 'figure')).toEqual([{ edition: 'ABS 2024-25', ready: 2, left: 1 }])
  // a figure has no name: counted as a locality it would not be ready
  expect(draftEditions(rows)).toEqual([{ edition: 'ABS 2024-25', ready: 0, left: 3 }])
})
