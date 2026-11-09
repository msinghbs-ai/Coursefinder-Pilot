// Guards: F-CDESC (Platform Admin decision 10 Nov 2026, course descriptions are AI-generated; operating rule 10 Nov 2026 05:40, only class-A settings): the narrow machine admission of FIRST course descriptions (migrations 20261110060000 and 20261110060100) is separate from the human Layer 4 route, ships off with one switch and no other setting, derives its limits from existing settings, writes only where the description is empty, reads back what it wrote, can be withdrawn by a named Platform Admin, and changes nothing the consumer API reads
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M1 = fs.readFileSync('supabase/migrations/20261110060000_cf247_cdesc_machine_policy_shadow.sql', 'utf8')
const M2 = fs.readFileSync('supabase/migrations/20261110060100_cf247_cdesc_machine_admission.sql', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const C1 = code(M1)
const C2 = code(M2)
const both = C1 + '\n' + C2
const run = fs.readFileSync('tests/fixtures/cdesc-machine/run.sh', 'utf8')
const scenarios = fs.readFileSync('tests/fixtures/cdesc-machine/scenarios.sql', 'utf8')
const workflow = fs.readFileSync('.github/workflows/course-descriptions-test.yml', 'utf8')
const fnBody = (c, name) => { const i = c.indexOf(`create or replace function ${name}(`); expect(i, name).toBeGreaterThan(-1); const j = c.indexOf('end $f$;', i); expect(j, name).toBeGreaterThan(i); return c.slice(i, j) }

test('the housekeeping lines are there and nothing is dropped or deleted', () => {
  for (const m of [M1, M2]) {
    expect(m).toMatch(/^-- Replaces: .+/m)
    expect(m).toMatch(/^-- Retires: .+/m)
  }
  for (const c of [C1, C2]) {
    // outside a function body no statement drops, deletes or truncates (a function body may delete a trigger-owned scratch row only if it says so; these do not)
    expect(c).not.toMatch(/^\s*(drop|truncate)\s/im)
    expect(c).not.toMatch(/^\s*delete\s+from\s/im)
  }
  expect(both).not.toMatch(/\bdrop\s+(table|function|trigger|index|column|schema)\b/i)
  expect(both).not.toMatch(/\bdelete\s+from\b/i)
  expect(both).not.toMatch(/\btruncate\b/i)
  expect(C1).toMatch(/comment on table pipeline\.course_description_machine_admissions is/)
  expect(C1).toMatch(/comment on table pipeline\.course_description_source_checks is/)
})

test('one new setting, the switch, ships 0; the refused-word and figures policy is the existing admission policy, not a parallel set', () => {
  const inserts = C1.match(/insert into pipeline\.platform_toolset_settings[\s\S]*?on conflict/g) || []
  expect(inserts.length).toBe(1)
  expect(C2).not.toMatch(/insert into pipeline\.platform_toolset_settings/)
  expect(inserts[0]).toContain("'enrich.course_description_machine_on'")
  expect(inserts[0]).toMatch(/'number', '0'::jsonb, 0, 1, 'on\/off'/)
  expect(inserts[0]).toContain('security.course_description_machine_admit_v1') // used_by line
  // every other value is derived from a setting that already exists (G2: no operational value written into code)
  for (const k of ['gaps.recheck_days', 'pdesc.duplicate_share', 'enrich.course_description_duplicate_window', 'enrich.course_text_items_per_day']) expect(both).toContain(`'${k}'`)
  expect(C1).toContain('security.pdesc_machine_text_check_ctx_v1(') // the existing wording policy, the same function the provider route calls
  expect(C1).toContain('security.course_description_check_v1(') // the existing sentence, support and in-provider duplicate checks
  // no setting value is changed and the human-first requirement is neither lowered nor read as a limit
  expect(both).not.toMatch(/update\s+pipeline\.platform_toolset_settings\s+set\s+value/i)
  expect(both).not.toMatch(/set_config|pipeline_set_setting|toolset_setting_set/i)
  expect(both.split('\n').filter((l) => l.includes("'enrich.course_description_review_first'") && !l.includes('post-check:')).length).toBe(0) // only the post-checks read it, to prove it is untouched
  expect(C1).toMatch(/post-check: review_first must be untouched/)
})

test('a limit written in code is a technical safety value and says so (-- fixed: <why>); a derived one says where it comes from', () => {
  const lines = both.split('\n')
  const timing = lines.filter((l) => /make_interval\(|interval '/.test(l))
  expect(timing.length).toBeGreaterThan(3)
  for (const l of timing) expect(l, l).toMatch(/-- (fixed|derived):|v_days|make_interval\(days => v_days\)|age_days/)
  for (const l of lines.filter((x) => /pipeline_num_v1\('(gaps|enrich|pdesc)\./.test(x) && !/machine_on/.test(x) && /v_(cap|days|share|win)\s+\w*\s*:?=?/.test(x))) expect(l, l).toMatch(/-- derived:|:= security\.pipeline_num_v1/)
  expect(C2).toMatch(/make_interval\(secs => 40\); -- fixed:/)
  expect(C2).toMatch(/make_interval\(hours => 1\) else make_interval\(days => v_days\) end, -- fixed:/)
})

test('honest wording: no reference to an object that does not exist, no claim that the page is read again; the switch is a human-class control and names the trust dependency', () => {
  expect(scenarios).toContain("help !~ 'course_text_verify|svc_course_description_source_check'") // the fixture proves the stored help text names neither
  for (const m of [M1, M2]) {
    expect(m).not.toContain('course_text_verify')
    expect(m).not.toContain('svc_course_description_source_check')
    expect(m).not.toMatch(/re-proves every quote|every sentence''s quote|re-checks every quote/)
  }
  expect(M1).toMatch(/nothing writes to it yet|Nothing writes to it yet/)
  expect(M1).toContain("control_class = 'human' where toolset_key = 'pipeline' and key = 'enrich.course_description_machine_on' and control_class is null")
  expect(M1).toContain("Machine approvals are not counted as a person''s trust: security.course_description_trusted_v1")
  // trust accounting is fixed where it is counted (one md5-guarded in-place edit with a held forward recovery), not documented as a hazard
  expect(M2).toContain("if md5(v_src) <> 'ae8b327f85f0262b3d0b878010a4af3c' then raise exception 'live security.course_description_trusted_v1(uuid) differs")
  expect(M2).toContain("and not exists (select 1 from pipeline.layer4_decisions md where md.review_item_id = r.id and md.layer2_state->>'actor_kind' = 'machine')")
  expect(M2).toContain("md5(v_src) = '16568089f58b528b9a6647e78eca3ed5'")
  const rec = fs.readFileSync('supabase/held/cdesc_trusted_machine_forward_recovery.sql', 'utf8')
  expect(rec).toContain("'ae8b327f85f0262b3d0b878010a4af3c'")
  expect(rec).toContain('CREATE OR REPLACE FUNCTION security.course_description_trusted_v1(p_provider uuid)')
  // the same test in the four existing measures: a machine decision is not a person's (each md5-guarded, in place, with a held forward recovery)
  const measures = [['security.course_description_summary_v1(uuid,boolean)', '8e284898fdc7bda9dcbcc9d85acabace', 'd5c88f55bcaadee970f7f3b2cc2ac25e'], ['security.course_description_capacity_v1()', 'ef83be9476da04995081ac04ab517bf0', '3ccb9929e42f7360056d7438570da110'],
    ['security.course_description_sample_report_v1()', '5854cf436c26cb814033f58a47e4d33e', '55b26a23b44a8ce8c5db8502ceabeb62'], ['security.layer4_pace_v1()', '344a3abad89b63baf9316a5d85f5f8ff', '5a90aa3d1d421902ebe48692bba2322c']]
  const rec2 = fs.readFileSync('supabase/held/cdesc_measures_machine_forward_recovery.sql', 'utf8')
  for (const [sig, before, after] of measures) {
    expect(M2, sig).toContain(`'${sig}', '${before}', '${after}'`)
    expect(rec2, sig).toContain(`v not in ('${after}', '${before}')`)
    expect(rec2, sig).toContain(`<> '${before}' then raise exception 'post-check`)
  }
  expect(M2).toContain("if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition this change edits")
  expect(M2).toContain("if md5(v_src) <> r.md5_after then raise exception '% after the edit has body md5 %, expected %'")
  expect(M2).toContain("and not l4.by_machine and l4.cur is not distinct from")
  expect(M2).toContain("'admitted_by_machine'")
  expect(M2).toContain("'approved_by_machine'")
  expect(M2).toContain("and x.actor_id is not null and coalesce(x.layer2_state->>'actor_kind', '') <> 'machine'")
  expect(rec2).toContain('CREATE OR REPLACE FUNCTION security.layer4_pace_v1()')
  // the margin test is "under 0.1" in the code, so the words say "under 0.1" or "at least 0.1", never "within 0.1"
  for (const m of [M1, M2]) expect(m).not.toMatch(/within 0\.1|clear margin|only just above/)
  expect(M1).toContain('a margin of at least 0.1')
  expect(M1).toContain('a margin under 0.1 declines')
  // applying again (a forward-recovery path) must not need the switch to be 0: both post-checks accept 0 or 1
  for (const m of [M1, M2]) {
    expect(m).toContain("security.pipeline_num_v1('enrich.course_description_machine_on', -1) not in (0, 1)")
    expect(m).not.toMatch(/machine_on', -1\) <> 0/)
  }
  // a recorded re-read counts only if recent and for the same copy
  const check = fnBody(C1, 'security.course_description_machine_check_v1')
  expect(check).toContain('sc.checked_at < now() - make_interval(days => v_days) or sc.content_hash_read is distinct from e.content_hash')
  expect(check).toContain("'source_recheck_unusable'")
  // identity strength: AI match or a thin margin goes to a person; the 0.1 is a marked fixed value (no setting exists and none is added)
  expect(check).toMatch(/g\.basis = 'ai_match' or \(g\.score is not null and g\.runner_up is not null and g\.score - g\.runner_up < 0\.1\) then -- fixed:/)
  expect(check).toContain("'identity_margin_thin'")
  // the near-duplicate window also covers the descriptions other providers' courses hold
  expect(check).toMatch(/union all[\s\S]*from catalogue\.courses d2[\s\S]*d2\.provider_id <> c\.provider_id[\s\S]*limit v_win\) w2/)
  // the job minute is not :13 (course-description-stale-retire and others fire there)
  const sched = /cron\.schedule\('course-description-machine', '([^']+)'/.exec(C2)
  expect(sched).not.toBeNull()
  expect(sched[1].split(' ')[0].split(',')).not.toContain('13')
})

test('the evaluator is read only and every decline carries one precise rule, a reason and a next action', () => {
  const check = fnBody(C1, 'security.course_description_machine_check_v1')
  expect(check).not.toMatch(/\b(insert|update|delete)\b\s+(into\s+)?(pipeline|catalogue|search|public)\./i)
  for (const rule of ['machine_admission_off', 'item_not_pending', 'course_not_active', 'provider_not_live', 'description_already_held', 'another_pending_item', 'manual_lock', 'manual_hold', 'rejected_before_course', 'rejected_before_page', 'rejected_before_text',
    'binding_ambiguous', 'identity_margin_thin', 'source_recheck_unusable', 'reading_other_course', 'evidence_moved', 'evidence_stale', 'lineage_hash_mismatch', 'object_missing', 'source_recheck_failed', 'page_url_changed', 'text_changed', 'reader_unrecorded', 'identity_not_allowed',
    'duplicate_exact_waiting', 'duplicate_exact_described', 'duplicate_near_other_provider', 'withdrawn_awaiting_person']) {
    expect(both, rule).toContain(rule)
  }
  expect(fnBody(C1, 'security.course_description_machine_shadow_v1')).not.toMatch(/\b(insert|update|delete)\b\s+(into\s+)?(pipeline|catalogue|search|public)\./i)
  expect(C1).toContain('security.cdesc_machine_fail_v1')
  expect(C1).toContain("security.cdesc_machine_fail_v1('policy_' || split_part(v_pol, ':', 1)") // the wording policy's own code names the decline (policy_refused_word, policy_figure, ...)
})

test('the admission: switch first, rows locked, the checks proved again at write time, the write read back from the catalogue and from the Website function, a machine actor, never the human decision route', () => {
  const admit = fnBody(C2, 'security.course_description_machine_admit_v1')
  expect(admit.indexOf("'enrich.course_description_machine_on'")).toBeGreaterThan(-1)
  expect(admit.indexOf("'enrich.course_description_machine_on'")).toBeLessThan(admit.indexOf('security.course_description_machine_check_v1'))
  expect(admit).toMatch(/for update/i)
  expect(admit).toContain('security.course_description_machine_check_v1(') // run again inside the write
  expect(admit).toMatch(/update catalogue\.courses set description = .* where id = .* and nullif\(btrim\(description\), ''\) is null/s) // only where the description is empty
  expect(admit).toContain('public.website_v2_course(') // read back, never changed
  expect(admit).toMatch(/matched|not_in_feed|lag/)
  expect(admit).toContain("raise exception 'cdesc:consumer_mismatch:") // a mismatch rolls the write back
  expect(admit).toContain("raise exception 'cdesc:description_not_written:") // a guard that restored the old text stops the claim
  expect(admit).toContain("'c0ffee00-0000-4000-8000-000000000150'") // the existing system automation account, not a person
  expect(admit).toContain("'actor_kind', 'machine'")
  expect(admit).toContain('pipeline.layer4_decisions')
  expect(admit).toContain('pipeline.admin_control_events')
  expect(admit).toContain('pipeline.search_refresh_signals')
  const noGuards = both.replace(/do \$g\$[\s\S]*?end \$g\$;/g, '') // the apply-order guards only name the functions that must exist
  expect(noGuards).not.toMatch(/layer4_review_decide_impl|layer4_course_description_apply_v1|admin_layer4_review_decide/) // the human route is not called, not simulated
  expect(M2).toMatch(/^-- Replaces: the person-trust count in security\.course_description_trusted_v1/m)
})

test('the hook: an after trigger on the reading (off does nothing, errors are swallowed, depth bounded), the record function and the Layer 4 triggers are not edited', () => {
  expect(C2).toMatch(/create or replace trigger field_enrich_items_cdesc_machine after update of state on pipeline\.field_enrich_items for each row/)
  expect(C2).toMatch(/when \(new\.state = 'review' and old\.state is distinct from 'review' and new\.field = 'description'\)/)
  const trg = fnBody(C2, 'security.course_description_machine_trg_v1')
  expect(trg).toContain('pg_trigger_depth() > 5')
  expect(trg).toContain("'enrich.course_description_machine_on', 0) < 1 then return null")
  expect(trg).toMatch(/exception when others then null/)
  // none of the live functions it sits beside is replaced here
  for (const f of ['enrich_course_text_record_v1', 'course_description_review_trg_v1', 'course_description_promote_held_v1', 'course_description_check_v1', 'layer4_course_description_apply_v1', 'pdesc_machine_text_check_ctx_v1']) {
    expect(both, f).not.toMatch(new RegExp(`create (or replace )?function [a-z_.]*${f}\\(`))
  }
})

test('withdrawal: Platform Admin (rank 6) only, a named person and a reason, restores the empty text only if nothing changed since, queues the refresh on the admission\'s own decision', () => {
  const pub = fnBody(C2, 'public.admin_course_description_machine_withdraw_v1')
  expect(pub).toMatch(/security\.current_role_rank\(\), 0\) < 6/)
  expect(pub).toContain('auth.uid()')
  expect(C2).toMatch(/revoke all on function public\.admin_course_description_machine_withdraw_v1\(uuid, text\) from public, anon;/)
  expect(C2).toMatch(/grant execute on function public\.admin_course_description_machine_withdraw_v1\(uuid, text\) to authenticated;/)
  const w = fnBody(C2, 'security.course_description_machine_withdraw_v1')
  expect(w).toContain("'c0ffee00-0000-4000-8000-000000000150'::uuid then raise exception 'the person who withdraws must be named'")
  for (const s of ['description_changed_since_admission', 'manual_lock', 'withdraw_not_applied', 'on conflict (review_decision_id) do update']) expect(w).toContain(s)
  for (const f of ['security.course_description_machine_admit_v1(uuid, text)', 'security.course_description_machine_withdraw_v1(uuid, text, uuid)', 'security.course_description_machine_settle_v1()', 'security.course_description_machine_run_v1()']) {
    expect(C2, f).toContain(`revoke all on function ${f} from public, anon, authenticated;`)
  }
})

test('the job: catalogued (G1) at rank 6 before it is scheduled, its command has no number, the run is bounded by existing settings and a time box', () => {
  const cat = C2.indexOf("insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage)")
  const sched = C2.indexOf("cron.schedule('course-description-machine'")
  expect(cat).toBeGreaterThan(-1)
  expect(sched).toBeGreaterThan(cat)
  const row = C2.slice(cat, C2.indexOf('on conflict', cat))
  expect(row).toContain("'course-description-machine'")
  expect(row).toMatch(/\n\s*6, false, null\)/) // control_rank 6, not batch editable
  const cmd = /\$j\$(select security\.course_description_machine_run_v1\(\))\$j\$/.exec(C2)
  expect(cmd).not.toBeNull()
  expect(cmd[1].replace(/_v1/g, '')).not.toMatch(/\d/)
  expect(fnBody(C2, 'security.course_description_machine_settle_v1')).toContain("'enrich.course_text_items_per_day'")
  expect(fnBody(C2, 'security.course_description_machine_settle_v1')).toContain('-- fixed:')
})

test('the ledger: one live admission per course, one decline per item, closed to the app, row level security on', () => {
  expect(C1).toContain('create unique index if not exists course_description_machine_admissions_live_uq')
  expect(C1).toMatch(/\(course_id\) where outcome = 'admitted' and withdrawn_at is null/)
  expect(C1).toContain('create unique index if not exists course_description_machine_admissions_declined_uq')
  expect(C1).toMatch(/\(review_item_id\) where outcome = 'declined'/)
  for (const t of ['course_description_machine_admissions', 'course_description_source_checks']) {
    expect(C1).toContain(`alter table pipeline.${t} enable row level security;`)
    expect(C1).toMatch(new RegExp(`revoke all on pipeline\\.${t} from public, anon, authenticated`))
  }
  for (const col of ['before_description', 'after_description', 'evidence_id', 'content_hash', 'source_url', 'model', 'prompt_version', 'rule', 'actor', 'reason_code', 'next_action', 'withdrawn_by', 'withdrawn_reason', 'consumer_check', 'recovery']) expect(C1, col).toContain(col)
})

test('the consumer API is not changed (G3): no consumer function is replaced, no column of a table it reads is altered, the only catalogue.courses writes are the empty description and the restore', () => {
  expect(both).not.toMatch(/create (or replace )?function (public\.)?(website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1)/)
  expect(both).not.toMatch(/create (or replace )?function api\./)
  expect(both).not.toMatch(/alter\s+table\s+(catalogue|ref|search|api|public)\.\w+\s+(drop|rename|alter)\b/i)
  expect(both).not.toMatch(/alter\s+table\s+catalogue\./i)
  expect(both).not.toMatch(/(update|insert into)\s+api\./i)
  const writes = [...both.matchAll(/update catalogue\.courses set ([a-z_]+)/g)].map((m) => m[1])
  expect(writes.length).toBe(2) // the admission and the withdrawal
  expect(new Set(writes)).toEqual(new Set(['description']))
  expect(C1).toMatch(/create index if not exists courses_description_norm_md5_idx on catalogue\.courses/) // an index beside the table, no column or row
  expect(M1).not.toContain('Consumer API change approved')
  expect(M2).not.toContain('Consumer API change approved')
})

test('the fixture harness proves it: refusals, no change on apply, applied twice, and the scenarios; it runs in the course-description workflow', () => {
  expect(run).toMatch(/^# Guards: F-CDESC/m)
  expect(scenarios).toMatch(/^-- Guards: F-CDESC/)
  for (const s of ['apply 20261110060000 first', 'applied again: no change', 'the new settings are not exactly the switch at 0', 'cdm: all']) expect(run, s).toContain(s)
  for (const s of ['wrong page', 'evidence_stale', 'evidence_moved', 'check_unsupported_marketing', 'policy_refused_word', 'policy_figure', 'check_not_stated', 'manual_lock', 'rejected_before_page', 'rejected_before_text',
    'check_duplicate_other_course', 'duplicate_exact_waiting', 'duplicate_near_other_provider', 'binding_ambiguous', 'provider_not_live', 'consumer_mismatch', "consumer_check = 'lag'", 'forward recovery', 'withdrawn_awaiting_person',
    'cap: with 2 items a day', 'a second settle admits nothing more', 'off: a fresh reading goes to Layer 4', 'trust accounting: machine approvals are not person-trust', 'summary: admitted by a person leaves out the machine admissions', 'capacity: approved ever and decided a day leave out the machine decisions', 'sample report: the approved count and approval share leave out the machine approvals', 'reviewer pace: machine decisions', 'back to the standing gap queue', 'identity_margin_thin', 'source_recheck_unusable']) {
    if (s === 'wrong page') continue // the wrong-page cases are evidence_moved and reading_other_course
    expect(scenarios, s).toContain(s)
  }
  expect(scenarios).toContain('reading_other_course')
  for (const s of ['measures_before.sql', 'measures_after.sql', 'applied again with the switch at 1', 'cdesc_measures_machine_forward_recovery.sql', 'the changed functions are not exactly the five edited ones']) expect(run, s).toContain(s)
  expect(workflow).toContain('tests/fixtures/cdesc-machine/')
  expect(workflow).toContain('bash tests/fixtures/cdesc-machine/run.sh')
  expect(workflow).toContain('supabase/migrations/2026111006*.sql')
})

test('visible results (Platform Admin 10 Nov 2026): wrong_page_kind and the Data Delivery stage counts are md5-guarded edits of functions we own, with forward recovery, no new setting and no new table', () => {
  const V = fs.readFileSync('supabase/migrations/20261110100000_cf247_cdesc_visible_results.sql', 'utf8')
  const W = fs.readFileSync('supabase/migrations/20261110100100_cf247_cdesc_wrong_page_kind.sql', 'utf8')
  for (const m of [V, W]) {
    expect(m).toMatch(/^-- Replaces: .+/m)
    expect(m).toMatch(/^-- Retires: .+/m)
    expect(m).not.toContain('Consumer API change approved')
    expect(code(m)).not.toMatch(/\b(drop|truncate)\s+(table|function|trigger|index|column|schema)?/i)
    expect(code(m)).not.toMatch(/\bcreate\s+table\b/i)
    expect(code(m)).not.toMatch(/insert\s+into\s+pipeline\.platform_toolset_settings/i)
  }
  // the edits are guarded by the md5 of the live body before and the body expected after
  expect(V).toContain('916e015e0cce905c97e17786b4c2ada1')
  expect(V).toContain('b67bd181c58546076da48e7b5f00a2a4')
  expect(W).toContain('fca43249b1846aae9eae0df7fc83ecb4')
  expect(W).toContain('3e0fe24d762e7fc4348865ea09499690')
  expect(code(V)).toContain("'stages', case when s.stream = 'cdesc' then security.data_delivery_cdesc_stages_v1() end")
  expect(code(W)).toContain("'wrong_page_kind'")
  // the top reasons use the existing setting, never a number in code
  expect(code(V)).toContain("security.pipeline_num_v1('data_delivery.reasons_shown', 3)")
  // the helper is not callable from outside
  expect(code(V)).toMatch(/revoke all on function security\.data_delivery_cdesc_stages_v1\(\) from public, anon, authenticated/)
  // forward recovery for both, accepting either the edited or the original body
  const HV = fs.readFileSync('supabase/held/cdesc_visible_results_forward_recovery.sql', 'utf8')
  const HW = fs.readFileSync('supabase/held/cdesc_wrong_page_kind_forward_recovery.sql', 'utf8')
  expect(HV).toContain('916e015e0cce905c97e17786b4c2ada1'); expect(HV).toContain('b67bd181c58546076da48e7b5f00a2a4')
  expect(HW).toContain('fca43249b1846aae9eae0df7fc83ecb4'); expect(HW).toContain('3e0fe24d762e7fc4348865ea09499690')
  // the harness runs the page kind checks on the migrated database (all pass) and on the old body (they must fail)
  expect(run).toContain('scenarios_visible.sql')
  expect(run).toContain('_oldchk')
  const sv = fs.readFileSync('tests/fixtures/cdesc-machine/scenarios_visible.sql', 'utf8')
  expect(sv).toMatch(/^-- Guards: F-CDESC/)
  for (const s of ['wrong_page_kind', 'entry-level', 'not served to the Website', 'never 0', 'known false']) expect(sv, s).toContain(s)
  expect(workflow).toContain('supabase/migrations/2026111010*.sql')
  expect(workflow).toContain('supabase/held/cdesc_*_forward_recovery.sql')
})
