// Guards: Admin destination data UI and ingestion specification v1.2 (RM0F; decisions G-2, G-3, G-5, Platform Admin 17 Nov 2026 11:52 and 13:12): the Destination data page sits after Rankings & statistics for Curator and above, every approval is the Platform Admin's with a reason, a postcode below the share is a Layer 4 Campus locality item, and campuses[].locality is a v3-only addition
// Behaviour is proven on isolated PostgreSQL by tests/fixtures/destination-admin-ui/run.sh (workflow destination-admin-ui-test); these checks keep the rules in the migration and the screens.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = (p) => fs.readFileSync(p, 'utf8')
const m = read('supabase/migrations/20261117131500_cf247_rm0f_destination_admin_ui.sql')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const nav = read('src/nav-map.js'), page = read('src/DestinationData.jsx'), main = read('src/mature-main.jsx')

test('G-2: Destination data is in the Catalogue menu after Rankings & statistics, with five tabs, each Curator and above', () => {
  expect(nav).toContain("'entry', 'rankings', 'destination', 'reference'")
  expect(nav).toContain("destination: { label: 'Destination data', slug: 'destination-data',")
  const block = nav.slice(nav.indexOf('destination: {'), nav.indexOf('  reference: {'))
  expect([...block.matchAll(/\{ key: '(\w+)', label: '([^']+)', min: (\d) \}/g)].map((x) => `${x[1]}|${x[2]}|${x[3]}`)).toEqual(
    ['overview|Overview & editions|3', 'localities|Localities & postcodes|3', 'metrics|City metrics & costs|3', 'rules|Study rules|3', 'careers|Careers & outcomes|3'])
  expect(main).toContain("case'destination':return <DestinationData tab={tab} rank={rank} onError={onError}/>")
  for (const t of ['overview', 'localities', 'metrics', 'rules', 'careers']) expect(page).toContain(`data-dst-tab="${t}"`)
})

test('every change on the page asks for a reason and is gated: approvals and editions at Platform Admin, postcodes at Curator', () => {
  expect(page).toContain("const ask=t=>{const r=window.prompt(`${t}\\n\\nReason (kept with the decision):`);return r&&r.trim().length>=4?r.trim():null}")
  // every action button names its rank; none of the status or edition actions is below 6, and the postcode actions are 3
  const acts = [...page.matchAll(/<Act label=[^>]*? need=\{(\d)\}[^>]*? data="([a-z-]+)"/g)].map((x) => `${x[2]}:${x[1]}`)
  expect(acts.sort()).toEqual(['career-approve:6', 'career-withdraw:6', 'edition-publish:6', 'edition-terms:6', 'locality-approve:6', 'locality-withdraw:6', 'metric-approve:6', 'metric-withdraw:6',
    'postcode-accept:3', 'postcode-choose:3', 'postcode-none:3', 'rule-approve:6', 'rule-withdraw:6'])
  expect(page).toContain("disabled={!ok} title={ok?undefined:`Needs ${need>=6?'Platform Admin':'Curator'}`}")
  // the server is the check: the wrappers refuse below their rank and without a reason
  for (const f of ['admin_destination_edition_set_terms', 'admin_destination_edition_publish']) {
    const body = code.slice(code.indexOf(`function public.${f}(`), code.indexOf('end $$;', code.indexOf(`function public.${f}(`)))
    expect(body).toContain('if coalesce(security.current_role_rank(), 0) < 6 then raise exception')
    expect(body).toContain("if v_reason is null then raise exception 'a reason is required'")
    expect(body).toContain("insert into pipeline.admin_control_events(area, action, target, detail, actor)")
  }
  const res = code.slice(code.indexOf('function public.admin_destination_postcode_resolve('), code.indexOf('end $$;', code.indexOf('function public.admin_destination_postcode_resolve(')))
  expect(res).toContain("if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required'")
  expect(code).toContain("if nullif(btrim(coalesce(p_reason, '')), '') is null then raise exception 'a reason is required'")
})

test('the page says what is fixed, what is missing and what is not earnings', () => {
  expect(page).toContain('Fixed. A change is a new edition.')
  expect(page).toContain('Edition published: fixed. Start a new edition to change it.')
  expect(page).toContain('This locality has no attribution text, so it cannot be approved.')
  expect(page).toContain('data-dst-quote-verifier'); expect(page).toContain('data-dst-stored-page'); expect(page).toContain('data-dst-applicability')
  expect(page).toContain('The funds a student must show for a visa are a study rule (category visa funds) and never appear in this table.')
  expect(page).toContain('if(rank<3)return <EmptyInline text="Destination data opens for Curator and above."/>')
})

test('G-3: Campus locality is a registered Layer 4 kind hook; the Inbox function itself is not replaced', () => {
  expect(code).toContain("values ('campus_locality', 'kind', 'security.layer4_campus_locality_kind_v1()', 'security.layer4_campus_locality_inbox_counts_v1()', 'security.layer4_campus_locality_inbox_page_v1(jsonb)',")
  expect(code).toContain("'security.layer4_campus_locality_inbox_detail_v1(text)', 'security.layer4_campus_locality_inbox_decide_v1(text,text,text,text)', true,")
  expect(code).not.toMatch(/create or replace function (public\.admin_layer4_inbox|security\.layer4_inbox_)/)
  expect(code).toContain("values ('layer4', 'inbox_decide', 'campus_locality:' || p_ref,")
  for (const k of ['accept_largest', 'choose_locality', 'no_locality']) expect(code).toContain(`{"key": "${k}", `)
  expect(code).toContain("limit least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200))  -- fixed: page size bounds, as the Inbox's own")
})

test('G-5: campuses[].locality is added by the v3 wrappers only, from an approved or published locality with a primary match', () => {
  expect(code).toContain("where p.country_code = upper(p_country_code) and p.postcode = nullif(btrim(p_postcode), '') and p.is_primary_match and l.status in ('approved', 'published')")
  expect((code.match(/'locality', /g) || []).length).toBeGreaterThanOrEqual(3)
  expect(code).toContain('create or replace function public.website_v3_provider_item(p_item jsonb)')
  expect(code).toContain('declare v jsonb := public.zoho_v2_provider(p_identifier);')
  expect(code).not.toMatch(/create or replace function (public\.(website|zoho)_v2_|public\.website_edge_|public\.zoho_edge_|api\.)/i)
  expect(code).not.toMatch(/destination_(import|row_guard|edition_guard)_v1\s*\(p|create or replace function security\.destination_edition_(publish|set_terms)_v1/)
  // the deploy step's own refusal test (scripts/ci/apply-migration.sh)
  expect(m).not.toMatch(/^(drop|delete|truncate)\b|^alter table .* drop /im)
})

test('adapted screens: Recognition card, provider cards, Destination loads, and the password reset is recorded', () => {
  const rec = read('src/CourseRecognition.jsx'), prov = read('src/ProviderDestination.jsx'), dd = read('src/DataDelivery.jsx'), ds = read('src/DetailSummary.jsx')
  expect(rec).toContain("supabase.rpc('admin_course_destination_read',{p_course_id:courseId})")
  expect(rec).toContain('data-recognition-schemes'); expect(rec).toContain('data-recognition-study-rules')
  expect(ds).toContain('{data.id&&<ProviderDestination providerId={data.id}/>}')
  expect(prov).toContain("' · Primary campus'"); expect(prov).toContain('It is never a provider registration.')
  expect(code).toContain("left join ref.registration_schemes s on s.scheme = lower(r.registration_scheme) and s.kind = 'provider_registration' and s.country_code = v_cc")
  expect(code).toContain("where c.provider_id = p_provider_id and lower(r.scheme) = 'pgwp'")
  expect(dd).toContain('<DestinationLoads rpc={rpc} rank={rank}/>')
  expect(page).toContain("rpc('admin_job_run_now_v1',{p_job:j.jobname,p_reason:r,p_args:{}})")
  expect(page).toContain("disabled={rank<Number(j.control_rank||6)}")
  const edge = read('supabase/functions/admin-user-management/index.ts')
  const reset = edge.slice(edge.indexOf('if (action === "reset_password") {'), edge.indexOf('if (action === "delete") {'))
  expect(reset).toContain('p_action: "password_reset_sent",')
  expect(reset.indexOf('resetPasswordForEmail')).toBeLessThan(reset.indexOf('password_reset_sent'))
  expect(code).toContain("if p_action not in ('user_created','user_invited','roles_replaced','user_disabled','user_enabled','password_reset_sent') then")
})
