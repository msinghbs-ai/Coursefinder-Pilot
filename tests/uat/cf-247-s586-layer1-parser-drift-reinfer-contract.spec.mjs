// Guards: Wave 2 addenda (Platform Admin 17 Nov 2026 19:08) and Mapper Contract v1.2 (drift and re-infer): a Layer 1 run that stops on its source layout flags drift on the source's parser line, a later completed run clears it, and waiting Re-infer Parser Spec requests are answered by a catalogued job through the AI mapper without resuming any source
// CF-247 S586. Migration 20261117233000_cf247_w2b_layer1_parser_drift_reinfer.sql; layer1-ai-induction-mapper 1.1.0 (action reinfer); shared reader _shared/cf247-layer1-read.ts.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261117233000_cf247_w2b_layer1_parser_drift_reinfer.sql', 'utf8')
const fn = fs.readFileSync('supabase/functions/layer1-ai-induction-mapper/index.ts', 'utf8')
const rd = fs.readFileSync('supabase/functions/_shared/cf247-layer1-read.ts', 'utf8')
const drift = (mig.match(/v_msg ~\* '([^']+)'/) || [])[1]

test('the drift trigger: layout wording from the readers flags drift; timeouts and HTTP errors do not; a completed run clears it; it never fails a run update', () => {
  expect(drift).toBeTruthy()
  const re = new RegExp(drift, 'i')
  for (const m of ['headers not found on Sheet1', 'required PRISMS headers missing', 'columns not found: Fee, Year', 'required workbook column missing {"headers":[]}',
    'CRICOS Courses payload does not contain expected identity column', 'Table 2: no SUA code / SUA name header row', 'sheet "Table 2" not found (sheets: x)']) expect(re.test(m), m).toBe(true)
  for (const m of ['svc_layer1_apply_register_records: canceling statement due to statement timeout', 'layer1-au-depth HTTP 504', 'run plan not found', 'invalid_run_nonce']) expect(re.test(m), m).toBe(false)
  expect(mig).toContain("after update of status on pipeline.layer1_run_queue")
  expect(mig).toContain("raise warning 'layer1 drift watch (run %): %', new.id, sqlerrm;  -- never fails the run update")
  expect(mig).toContain("p.drift_flagged_at < coalesce(new.started_at, now())")
  expect(mig).toContain("insert into pipeline.layer1_source_parsers(source_id, parser_kind) values (p_source_id, 'hardcoded') on conflict (source_id) do nothing;")
})

test('the re-infer job is catalogued, fires only when a request waits, and passes its batch from a setting', () => {
  expect(mig.indexOf("('layer1-parser-reinfer', 'Layer 1 register'")).toBeLessThan(mig.indexOf("cron.schedule('layer1-parser-reinfer'"))
  expect(mig).toContain("where security.layer1_parser_reinfer_due_v1()')")
  expect(mig).toContain("security.pipeline_num_v1(''batch.layer1_parser_reinfer'', 3)::int")
  expect(mig).toContain("('pipeline', 'layer1.declarative_max_file_mb', ")
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('the mapper answers re-infer only with a nonce; hardcoded parsers are skipped; a new spec is recorded only when it passes the check; nothing resumes a source', () => {
  expect(fn).toContain('if (body.action !== "reinfer") return fail("Only reinfer runs with a nonce.", 400);')
  expect(fn).toContain('if (body.action === "reinfer") return fail("Re-infer runs from its job.", 403);')
  expect(fn).toContain('if (it.parser_kind !== "ai_built") {')
  expect(fn).toContain('if (!proposal.validation.ok || !proposal.parser_spec) {')
  expect(fn).toContain('spec_by: "ai_reinfer"')
  expect(fn).not.toMatch(/paused\s*[:=]\s*false|resume/i)
  expect(rd).not.toMatch(/\beval\(|new Function\(/)
  expect(rd).toContain('throw new Error(`format ${format} is not read by the declarative reader (csv, xlsx and json are)`);')
})
