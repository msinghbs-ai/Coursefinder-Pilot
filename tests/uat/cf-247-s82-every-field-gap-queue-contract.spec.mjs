import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// CF-247 v2.15.303 (Platform Admin, 21 Oct 2026 07:30): every field on Coverage, a standing queue that keeps filling missing fields,
// and a cross-check that never overwrites. Choices: "Stored pages + AI, small reads", "When page changes, or 60 days",
// "All on Coverage; queue for readable ones".
const m = fs.readFileSync('supabase/migrations/20261021110000_cf247_field_register_gap_queue.sql', 'utf8')
const ui = fs.readFileSync('src/FieldCoverage.jsx', 'utf8')
const cov = fs.readFileSync('src/course-coverage.jsx', 'utf8')

test('field register holds every course and provider field with a target', () => {
  for (const f of ['official_url', 'level', 'field_of_study', 'duration', 'delivery', 'campus', 'campus_city', 'international', 'provider_tuition',
    'registered_tuition', 'intakes', 'deadline', 'english', 'academic_entry', 'description']) expect(m).toContain(`('${f}', 'course',`)
  for (const f of ['p_website', 'p_address', 'p_campuses', 'p_type', 'p_international', 'p_logo', 'p_contact', 'p_scholarships', 'p_description'])
    expect(m).toContain(`('${f}', 'provider',`)
  expect(m).toContain("target_pct numeric not null default 80")
  expect(m).toContain("comment on table pipeline.field_register")
  // the coverage read takes its list from the register, not a fixed 7
  expect(m).toContain("c_attrs text[]:=array(select f.field from pipeline.field_register f where f.level='course' and f.active order by f.sort);")
})

test('standing gap queue: scheduled, catalogued, settings-driven, capped reads, re-check rule and the flag hold', () => {
  expect(m).toContain("select cron.schedule('field-gap-queue', '23 */6 * * *', $$select security.field_gap_queue_tick_v1()$$);")
  expect(m).toContain("insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values\n ('field-gap-queue'")
  for (const k of ['gaps.recheck_days', 'gaps.items_per_run', 'gaps.scraper_reads_per_day', 'crosscheck.duration_tolerance_pct']) {
    expect(m).toContain(`('pipeline', '${k}'`)
    expect(m).toContain(`security.pipeline_num_v1('${k}'`)
  }
  expect(m).toContain("continue when v_src = 'scraper' and coalesce((j.args->>'standing')::boolean, false) and not security.gap_scraper_room_v1();")
  expect(m).toContain("f.flagged_at > now() - make_interval(days => security.pipeline_num_v1('gaps.recheck_days', 60)::int)")
  expect(m).toContain("if security.enrich_item_held_v1(new.course_id, new.field) then return null; end if;")
  expect(m).toContain("coalesce(l.state, '') not in ('queued', 'waiting', 'ai', 'leased', 'review')")
  expect(m).toContain("'enrich-standing'")
  expect(m).toMatch(/-- Replaces: /)
  expect(m).toMatch(/-- Retires: /)
})

test('cross-check records differences and never overwrites; a person decides', () => {
  expect(m).toContain('create table if not exists pipeline.field_crosscheck_findings')
  expect(m).toContain("on conflict (course_id, field, page_value) do nothing;")
  expect(m).not.toMatch(/update catalogue\.courses[^;]*from pipeline\.field_crosscheck_findings/)
  expect(m).toContain("if v_rank < 4 then raise exception 'Pipeline Operator role or above required'")
  expect(m).toContain("insert into pipeline.manual_locks(entity, entity_id, field, mode, set_by) values ('course', v_f.course_id, v_f.field, 'value', auth.uid())")
  expect(m).toContain("Consumer API not touched (Decision 266)")
})

test('Coverage › Attributes shows every field, the queue and the cross-check', () => {
  expect(ui).toContain("supabase.rpc('admin_field_coverage'")
  expect(ui).toContain('data-field-matrix={level}')
  expect(ui).toContain('data-gap-queue')
  expect(ui).toContain('data-crosscheck')
  expect(ui).toContain("call('target_set'")
  expect(ui).toContain("call('queue_set'")
  expect(ui).toContain("call('run_now')")
  expect(cov).toContain("in_queue:'In the fill queue (Enrich fields)',no_reader:'No reader yet'")
  for (const f of ['level', 'field_of_study', 'delivery', 'campus_city', 'international', 'deadline', 'academic_entry', 'description']) expect(cov).toContain(`${f}:{label:`)
})

// v2.15.304 (Platform Admin, 21 Oct 2026 08:42): "go ahead with next step for Field Stalled and action to resolve it. and 10-min check up -
// should update in the guide/SOP"
test('stalled fields: daily history, rules from settings, health check, actions, guide and SOPs', () => {
  const s = fs.readFileSync('supabase/migrations/20261021130000_cf247_field_stalled.sql', 'utf8')
  const sops = fs.readFileSync('src/guide/sops.js', 'utf8')
  const guide = fs.readFileSync('src/guide/platformGuide.js', 'utf8')
  const health = fs.readFileSync('src/PlatformHealth.jsx', 'utf8')
  const ui2 = fs.readFileSync('src/FieldCoverage.jsx', 'utf8')
  expect(s).toContain('create table if not exists pipeline.field_coverage_daily')
  for (const k of ['stall.days', 'stall.min_points', 'stall.country_gap_points', 'stall.queue_hours']) expect(s).toContain(`security.pipeline_num_v1('${k}'`)
  expect(s).toContain("if security.platform_health_due_v1('field_stalled',p_force) then")
  expect(s).toContain("values ('field_stalled', 'coverage sweep', 'Fields below target are moving'")
  expect(s).toContain("elsif p_action in ('fill_now', 'release_and_fill') then")
  expect(s).toContain("if v_rank < 6 then raise exception 'Platform Admin role required'")
  expect(s).toMatch(/-- Replaces: /)
  expect(s).toMatch(/-- Retires: /)
  expect(ui2).toContain("call('stalled',scope)")
  expect(ui2).toContain('data-stalled-fields')
  expect(health).toContain("field_stalled:['#coverage?tab=attributes','Coverage › Attributes › Stalled fields']")
  expect(sops).toContain('10-minute field check, 1 of 4.')
  expect(sops).toContain("role: 'Pipeline Operator', do: '10-minute field check.")
  expect(guide).toContain('The 10-minute check (weekly)')
})
