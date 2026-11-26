// Guards: DR-19 (SS-Programme-Control 26 Nov 2026 19:19 AEDT, Platform Admin execution mandate "Intelligent monitoring and human-assisted resolution"), s1272: every Layer 4 card has a Processing journey and diagnosis fold that reads public.admin_record_journey_v1 (eight stages, the stopping stage and why later stages are not reached, and the diagnosis); unavailable, not verified and zero are kept apart; the read is read only (no model call, no spend) at Curator and above; the authorised actions are the card's existing decisions; no new page or navigation
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = p => fs.readFileSync(p, 'utf8')
const MIG = 'supabase/migrations/20261129200000_cf247_s1272_dr19_record_journey.sql'
const m = read(MIG)
const STAGES = ['discovery', 'acquisition', 'extraction', 'normalisation', 'validation', 'admission', 'publication', 'verification']

test('migration: read only, guarded, two G2 settings, nothing dropped', () => {
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: /m)
  expect(m).not.toMatch(/\bdrop\s+(table|function|view|index|schema)\b/i); expect(m).not.toMatch(/\bdelete\s+from\b/i)
  expect(m).not.toMatch(/\b(insert|update)\s+(into\s+)?(catalogue|pipeline\.layer4|scholarship)\./i)
  expect(m).not.toMatch(/openrouter\.ai|\bnet\.http|firecrawl_|security\.fc_/i)  // no model or paid fetch is called
  expect(m).not.toMatch(/create table (?!s1272_guard)/i)
  for (const k of ['layer4.journey_similar_days', 'layer4.journey_similar_max']) {
    expect(m).toContain(`'${k}'`)
    expect(m).toContain(`security.pipeline_num_v1('${k}',`)
  }
  expect(m).toContain('security.consumer_api_check_v1()')
  expect(m).toContain("'post-check: the number of active cron jobs changed'")
  expect(m).toContain("'post-check: manual locks changed'")
})

test('the read: Curator and above, eight stages, a stopping stage, later stages not reached', () => {
  const pub = m.slice(m.indexOf('create or replace function public.admin_record_journey_v1('))
  expect(pub).toContain("if auth.uid() is null then raise exception 'authentication required'")
  expect(pub).toContain('if security.current_role_rank() < 3 then')
  expect(m).toMatch(/revoke all on function public\.admin_record_journey_v1\(jsonb\) from public, anon/)
  expect(m).toMatch(/revoke all on function security\.record_journey_v1\(text, text\) from public, anon, authenticated/)
  for (const s of STAGES) expect(m).toContain(`'${s}'`)
  expect(m).toContain("where s->>'state' in ('failed', 'held', 'not_started');  -- unavailable is no record, not a stop")
  expect(m).toContain("'Not reached: waits for ' || lower(")
  expect(m).toContain("'not_verified'")
  expect(m).toContain("'No AI analysis has been run for this record. The platform runs one only when automatic recovery fails, so nothing was spent.'")
  expect(m).toContain("'usd', 0, 'basis', 'no AI and no Firecrawl'")
})

test('the fold: on every Layer 4 card, read when opened, actions are the card decisions', () => {
  const inbox = read('src/Layer4Inbox.jsx'), j = read('src/Layer4Journey.jsx')
  expect(inbox).toContain('<Layer4Journey kind={it.kind} refId={it.ref} actions={orderChoices(cdChoiceShown).map(c=>({label:c.label,need:needs(c),allowed:rank>=needs(c)&&!gated(c)}))}/>')
  expect(j).toContain("supabase.rpc('admin_record_journey_v1',{p_args:{kind,ref}})")
  expect(j).toContain('<details className="l4z-fold l4j" data-l4-fold="journey"')
  expect(j).toContain('<summary>Processing journey and diagnosis</summary>')
  expect(j).toMatch(/onToggle=\{e=>\{if\(e\.currentTarget\.open&&!j&&!busy\)load\(\)\}\}/)
  // unavailable, not verified and zero are kept apart
  expect(j).toContain("not_verified:['Not verified','info'],unavailable:['Not available','neutral']")
  expect(j).toContain('Not available{why?')
  expect(j).toContain("`0 in the last ${sim.days} days`")
  expect(j).toContain('c.usd==null?<NA why={c.basis}/>')
  // nothing decided in the screen: no stage rule written here
  expect(j).not.toMatch(/state\s*=\s*['"](done|failed|held)['"]/)
  // no new page, tab or navigation
  expect(read('src/nav-map.js')).not.toContain('Layer4Journey')
})

test('phone width: the stage strip wraps and the fold controls are 44 px', () => {
  const css = read('src/layer4-item-lifecycle.css'), b = css.slice(css.indexOf('/* CF-247 s1272'))
  expect(b).toContain('grid-template-columns:repeat(auto-fill,minmax(min(100%,11rem),1fr))')
  expect(b).toContain('.l4j summary{min-height:44px')
  expect(b).toContain('.l4j-refresh{min-height:44px')
})

test('the guide names the fold', () => {
  const g = read('src/guide/layer4Guide.js')
  expect(g).toContain("Processing journey and diagnosis (DR-19, s1272): ")
  expect(read('docs/UI-MAP.md')).toContain('Processing journey and diagnosis (details) — Layer4Journey.jsx')
})
