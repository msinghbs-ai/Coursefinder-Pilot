// Guards: CF-247 UI audit Phase 1 (Platform Admin 24 Oct 2026): list views carry no internals.
// CF-247 UI audit Phase 1 (Platform Admin 24 Oct 2026): list views carry no internals. Stable keys, record ids, hashes, job slugs,
// model identifiers, cron text and route fragments leave the rows; every value stays reachable behind the detail, a hover title or a
// closed fold. Vendor balances are figures for the Platform Admin (rank 6) and words for everyone else; the Go-live checklist is
// Platform Admin only. Presentation layer only: no migration, no RPC change.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const ui = fs.readFileSync('src/mature-main.jsx', 'utf8')
const pc = fs.readFileSync('src/ProviderContactsWorkspace.jsx', 'utf8')
const refs = fs.readFileSync('src/ReferenceSources.jsx', 'utf8')
const health = fs.readFileSync('src/PlatformHealth.jsx', 'utf8')
const queues = fs.readFileSync('src/QueueWatch.jsx', 'utf8')
const autos = fs.readFileSync('src/Automations.jsx', 'utf8')
const sched = fs.readFileSync('src/ScheduledJobsWorkspace.jsx', 'utf8')
const evidence = fs.readFileSync('src/EvidenceWorkspace.jsx', 'utf8')
const models = fs.readFileSync('src/ModelsServices.jsx', 'utf8')
const ai = fs.readFileSync('src/AiConfig.jsx', 'utf8')
const toolsets = fs.readFileSync('src/Toolsets.jsx', 'utf8')
const fcWork = fs.readFileSync('src/FirecrawlWork.jsx', 'utf8')
const nav = fs.readFileSync('src/nav-map.js', 'utf8')
const users = fs.readFileSync('src/access-roles-entry.jsx', 'utf8')
const viewer = fs.readFileSync('src/lib/viewer.js', 'utf8')
const format = fs.readFileSync('src/lib/format.js', 'utf8')

test('Courses, Providers, Campuses, Scholarships: no stable key under the name; a GUID course code is a dash; identifiers sit closed in the drawer for Curators and above', () => {
  expect(ui).not.toContain('<small>{r.stable_key}</small>')
  expect(ui).toContain('data-stable-key={r.stable_key||undefined}')
  expect(ui).toContain("const isGuid=v=>/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(v||''))")
  expect(ui).toContain("if(!c||isGuid(c))return'—';return r.code_kind==='studysearch'")
  expect(ui).toContain("minCompleteness:'Minimum completeness'")
  expect(ui).not.toContain('Min legacy presence')
  expect(ui).toContain('function Identifiers({data,rank}){const[open,setOpen]=useState(false);if(!(Number(rank)>=3)||!data||(!data.id&&!data.stable_key))return null;return <details className="ds-more" data-identifiers onToggle={e=>setOpen(e.currentTarget.open)}><summary>Identifiers (for support)</summary>{open&&')
  expect(ui).toContain('<DetailDrawer type={type} data={detail} busy={detailBusy} rank={rank}')
  // the drawer still hides raw ids from the generic fact cards
  expect(ui).toContain("const hidden=k=>k==='id'||k==='stable_key'||k.endsWith('_id')||k.includes('hash')")
})

test('Rankings & statistics: the kicker names its own screen, the import row says when the file was uploaded (name on hover), the job reads as "Ranking import", a date range reads as a person says it', () => {
  expect(ui).toContain('<div className="m-section-kicker">Rankings &amp; statistics / Ranking imports</div>')
  expect(ui).not.toContain('<span>{x.original_filename}</span>')
  expect(ui).toContain("<span title={x.original_filename||undefined} data-import-file>{x.uploaded_at?'File uploaded '+fmtDate(x.uploaded_at):'File uploaded'}</span>")
  expect(ui).toContain("Latest job: {jobTypeLabel(job.job_type)}")
  expect(ui).toContain("const JOB_TYPE_LABEL={layer1_ranking_etl:'Ranking import'")
  expect(ui).not.toContain('Layer 1 Ranking ETL')
  expect(ui).toContain('const pPeriod=p?fmtPeriod(p.period_start,p.period_end):')
  expect(format).toContain('export function fmtPeriod(start, end, fallback = EMPTY)')
  expect(format).toContain("if (pa.y === pb.y && pa.mo === 0 && pa.d === 1 && pb.mo === 11 && pb.d === 31) return String(pa.y)")
})

test('Provider contacts: the hero band is gone (a plain toolbar holds the actions); the provider stable key left the row', () => {
  expect(pc).not.toContain('pc-hero ')
  expect(pc).toContain('<div className="pc-toolbar" data-pc-toolbar>')
  expect(pc).not.toContain('<small>{row.provider_stable_key||row.country_code||\'\'}</small>')
  expect(pc).toContain("<small title={row.provider_stable_key||undefined}>{row.country_code||''}</small>")
})

test('Reference sources: the last check reads in words with the HTTP number on hover; the rule chip reads "Not a university site"', () => {
  expect(refs).toContain("export function httpWords(code){const n=Number(code);if(!Number.isFinite(n)||n<=0)return'Not checked';if(n>=200&&n<300)return'Reachable';if(n===401||n===403)return'Refuses automated reads';if(n===404||n===410)return'Page gone';if(n===429)return'Asked us to slow down';if(n>=500)return'Site error';return'Not checked'}")
  expect(refs).toContain('title={x.http?`HTTP ${x.http}`:undefined} data-http={x.http||undefined}>{x.http?`${httpWords(x.http)} · `:\'\'}')
  expect(refs).not.toContain('{x.http?`HTTP ${x.http} · `:\'\'}')
  expect(refs).toContain("const USE_CHIP={not_provider_site:'Not a university site'}")
  expect(refs).toContain('<Metric label="Not a university site"')
  expect(refs).not.toContain('<Metric label="Never a university website"')
})

test('Platform health: route fragments become screen-named links, cron text becomes schedule words, the heading does not repeat the health dot sentence', () => {
  expect(health).toContain("import{describeSchedule}from'./automation-schedule'")
  expect(health).toContain('export function isRouteFragment(v)')
  expect(health).toContain('export function ScreenLink({href,prefix=\'Go to \'}){return <a className="ph-fix" href={href} data-screen-link>{prefix}{screenName(href)}</a>}')
  expect(health).toContain('if(isRouteFragment(v))return screenName(v);if(looksCron(v))return describeSchedule(v).text;')
  expect(health).toContain('if(isRouteFragment(value))return <span className="ph-detail"><ScreenLink href={String(value).trim()}/></span>')
  expect(health).toContain("const PAGE_WORDS={ok:'Every check passed',warning:'Some checks need attention',critical:'Fix the critical checks first'")
  expect(health).toContain('<h2 data-health-heading>{PAGE_WORDS[tone]}</h2>')
  expect(health).not.toContain('<h2>{HEALTH_WORDS[tone]}</h2>')
  expect(queues).toContain('<ScreenLink href={q.fix_at}/>')
  expect(queues).not.toContain('Go to the screen')
})

test('Scheduled jobs: the row shows the label only (slug on hover and in data-job); decision references leave the description; target ids sit on hover', () => {
  expect(autos).toContain("export const plainDescription=t=>String(t||'').replace(/\\s*\\((?:Decision|Decisions)\\s+\\d+[^)]*\\)/gi,'')")
  expect(autos).toContain('<tr className={j.active?\'\':\'l3c-off\'} data-job={j.job}>')
  expect(autos).toContain('<td title={j.job}><strong>{j.label||j.job}</strong><span className="au-desc" title={j.description||undefined}>{plainDescription(j.description)}</span>')
  expect(autos).not.toContain('<span className="l3v-code">{j.job}</span>')
  expect(sched).toContain('target:<td key={id} title={technicalTarget(p)} data-target={technicalTarget(p)}>')
})

test('Evidence: no id or hash fragments in the list; job slugs and state strings read as words', () => {
  expect(evidence).not.toContain('shortId(')
  expect(evidence).not.toContain('r.content_hash.slice(0,12)')
  expect(evidence).toContain('<td data-evidence-id={r.id}><span className="evidence-artifact"><FileCheck2 size={15}/><span><strong>{evidenceKind(r.evidence_type)}</strong>')
  expect(evidence).toContain("<td data-content-hash={r.content_hash||undefined}><strong>{r.storage_available?'File is stored':'Details only'}</strong>")
  expect(evidence).not.toContain("'Private object present'")
  expect(evidence).toContain("const STATE_WORDS={missing_extraction:'Not yet read',has_extraction:'Read',extracted:'Read',no_policy:'No reading rule',current_or_unversioned:'Current copy'")
  expect(evidence).toContain("const JOB_WORDS={provider_course_page_sweep:'Course page sweep'")
  // the detail still carries the hash, job id and evidence id
  expect(evidence).toContain("['Content hash',file.content_hash,'mono']")
  expect(evidence).toContain("['Evidence id',d.id||id,'mono']")
})

test('Models & services: the list names the model (identifier behind Identifier / on hover); balances are figures for the Platform Admin and words for everyone else', () => {
  expect(viewer).toContain('export const PLATFORM_ADMIN_RANK=6')
  expect(viewer).toContain('export function useIsPlatformAdmin(){return useViewerRank()>=PLATFORM_ADMIN_RANK}')
  expect(viewer).toContain("export function balanceWords(remaining,floor=0)")
  expect(viewer).toContain("return'Used up'"); expect(viewer).toContain("return'Near the limit'"); expect(viewer).toContain("return'Within budget'")
  expect(ui).toContain("import{ViewerContext}from'./lib/viewer'")
  expect(ui).toContain('<ViewerContext.Provider value={{rank}}>')
  expect(models).toContain('export function modelLabel(id)')
  expect(models).toContain('<td title={m.model}><strong>{modelLabel(m.model)}</strong>')
  expect(models).toContain('<details className="ms-ident" data-model-id={m.model}><summary>Identifier</summary><code>{m.model}</code></details>')
  expect(models).not.toContain('<td><strong>{m.model}</strong>')
  expect(ai).toContain("data-balance={admin?'figure':'words'}>{admin?`${money(b.remaining_usd)} left`:words}")
  expect(ai).toContain('<strong>{admin?money(b.remaining_usd):words}</strong>')
  expect(ai).toContain('title={m.model}>{modelLabel(m.model)}')
  expect(toolsets).toContain("data-balance={admin?'figure':'words'}>{admin?`${fmtNumber(p.used)} of ${fmtNumber(p.credits)} credits used`:balanceWords(p.left,p.reserve)}")
  expect(toolsets).toContain("<p data-balance={admin?'figure':'words'}>{admin?<><strong>Balance {money(b.remaining_usd)}</strong>")
  expect(fcWork).toContain("{admin?`${fmtNumber(v.remaining)} of ${fmtNumber(v.plan_credits)} credits left`:`Credits: ${balanceWords(v.remaining,b.stop_at_remaining_units)}`}")
})

test('Go-live checklist is Platform Admin only (nav-map min 6); the shell refuses the page below that rank', () => {
  expect(nav).toMatch(/migration: \{ label: 'Go-live checklist', slug: 'environment-migration', icon: 'shield', min: 6,/)
  expect(ui).toContain('if(!canOpen(pageKey,rank))return <EmptyState icon={AlertTriangle} title="Not authorised"')
})

test('Users & roles: no id fragments in rows (id on hover); the system account reads as Platform automation', () => {
  expect(users).not.toContain('shortId(')
  expect(users).toContain('<tr key={user.id} data-user-id={user.id}><td><strong title={user.id}>{accountLabel(user.email)}</strong>')
  expect(users).toContain("export const accountLabel=email=>email?(isSystemAccount(email)?'Platform automation (system account)':email):'No email'")
})
