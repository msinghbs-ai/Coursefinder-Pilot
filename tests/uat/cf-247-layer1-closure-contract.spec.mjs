import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// CF-247 Layer 1 closure (Decision 159). These contracts fail if any closed Layer 1 behaviour is removed.
const read=p=>fs.readFileSync(p,'utf8')

test('Register departures: CRICOS plan finish and NZQA seen tracking, same hold and audit',async()=>{
  const m=read('supabase/migrations/20260928090200_layer1_seen_tracking_departures_and_reverify.sql')
  expect(m).toContain('create or replace function security.layer1_seen_departures_v1(')
  expect(m).toContain("v_limit:=greatest(50, ceil(v_total*0.02)::int);")
  expect(m).toContain('pr.checked_at>=v_since')                       // only providers read in this run
  expect(m).toContain("insert into pipeline.layer1_course_retirements(")
  expect(m).toContain("security.consumer_api_snapshot_v1()")
  expect(m).toContain('create trigger trg_layer1_seen_departures after update of status on pipeline.layer1_run_queue')
  expect(m).toContain("if p.course_hash=''seen-tracking'' then return security.layer1_seen_departures_v1")
  // R14: rows seen in a run are re-marked checked at most every 30 days
  expect(m).toContain("c.last_verified_at<now()-interval ''30 days''")
})

test('Run summary counts active records; provider departures reviewed in Layer 4',async()=>{
  const f=read('supabase/migrations/20260928090000_layer1_finalize_counts_active.sql')
  expect(f).toContain("lower(scheme)='cricos' and status='active'")
  expect(f).toContain("'retired', jsonb_build_object(")
  const d=read('supabase/migrations/20260928090100_layer4_provider_departures_review.sql')
  expect(d).toContain("if p_decision not in ('closed','merged','reviewed')")
  expect(d).toContain("security.current_role_rank()<6")
  expect(d).toContain("'merged_into'")
  const ui=read('src/layer4-mass-operations-entry.jsx')
  expect(ui).toContain("['departures','Provider departures']")
  expect(ui).toContain("rpc('layer4_provider_departure_decide'")
})

test('Scheduled verification covers every Layer 1 source kind',async()=>{
  const s=read('supabase/migrations/20260928090300_layer1_scheduler_global_sources.sql')
  expect(s).toContain("coalesce(c.iso_alpha2::text,''GLOBAL'')")
  const w=read('supabase/functions/layer1-operations-scheduled/index.ts')
  expect(w).toContain('async function invokeStatWorker(')
  expect(w).toContain('function qiltSurvey(')
  expect(w).toContain('if(system==="QS"||system==="THE")')
  expect(w).toContain('svc_ranking_applied_import_for_source')
  const q=read('supabase/migrations/20260928050000_layer1_run_queue_global_country.sql')
  expect(q).toContain("v_country:=coalesce(v_country,''GLOBAL'');")
})

test('Rankings: validated uploads applied internally; THE files checked against their declared year',async()=>{
  const c=read('supabase/functions/ranking-publisher-control/index.ts')
  expect(c).toContain('internal callers may only apply a validated import')
  expect(c).toContain('const SYSTEM_ACTOR="c0ffee00-0000-4000-8000-000000000150"')
  const e=read('supabase/functions/ranking-layer1-etl/index.ts')
  expect(e).toContain('if(systemCode==="the_wur"&&/^Year\\s+\\d{4}\\s*[\\r\\n]/i.test(text))')
  expect(e).toContain('THE file year ${declaredYear} does not match selected edition ${expectedYear}')
  expect(read('supabase/migrations/20260928091000_r5_qs_2025_edition_restore.sql')).toContain('v_region<1500 or v_au<30')
  expect(read('supabase/migrations/20260928091100_r5_the_2015_withdrawn.sql')).toContain('v_same<>v_n15')
})

test('Statistics editions: discovery from stable pages, checked before a person applies',async()=>{
  const m=read('supabase/migrations/20260928092000_d134_statistics_edition_discovery.sql')
  expect(m).toContain('create table if not exists pipeline.statistics_edition_rules(')
  expect(m).toContain("'https://www.qilt.edu.au/surveys/graduate-outcomes-survey-(gos)'")
  const d=read('supabase/functions/statistics-edition-discovery/index.ts')
  expect(d).toContain('mode: "dry_run"')
  expect(d).not.toContain('mode: "apply"')                            // discovery never applies
  const ctl=read('supabase/functions/layer1-operations-control/index.ts')
  expect(ctl).toContain('if(action==="apply_edition"){await requireOperator(service,auth.userId);')
  expect(ctl).toContain('only a checked edition can be applied')
  expect(read('supabase/functions/qilt-au-etl/index.ts')).toContain('edition file must be on qilt.edu.au')
  expect(read('supabase/functions/prisms-au-etl/index.ts')).toContain('edition file must be an education.gov.au download')
  const ui=read('src/layer1-operations-entry.jsx')
  expect(ui).toContain('function QiltFamilyCard(')
  expect(ui).toContain('function NewEditions(')
  expect(ui).toContain("control({action:'apply_edition',candidate_id:c.id})")
})

test('Identity is country-scoped (Decision 149)',async()=>{
  const m=read('supabase/migrations/20260928080000_d149_country_scoped_identifiers.sql')
  expect(m).toContain('create trigger trg_mirror_course_registration_identifier')
  expect(m).toContain('create trigger trg_mirror_provider_registration_identifier')
})
