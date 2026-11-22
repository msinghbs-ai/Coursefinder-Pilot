// Guards: Platform Admin 23 Nov 2026 08:47 AEDT (S2-Build s980): migration pre-flight before any push; the rolled-back dry-run gate runs only for pull requests to main that add a migration; rehearsals and read-back probes never fail a run.
// Pure code contract: the workflow, the dry-run script, the pre-flight script and the pre-push hook.
import { test, expect } from '@playwright/test';
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

const wf = fs.readFileSync('.github/workflows/db-migration-dry-run.yml', 'utf8');
const run = fs.readFileSync('scripts/ci/dry-run-migration.sh', 'utf8');
const pre = fs.readFileSync('scripts/ci/migration-preflight.mjs', 'utf8');
const hook = fs.readFileSync('.githooks/pre-push', 'utf8');

test('s980: no push trigger; the gate is pull requests to main that add a migration, labelled live-dry-run', () => {
  const on = wf.slice(wf.indexOf('\non:'), wf.indexOf('\njobs:'));
  expect(on).not.toMatch(/\n\s+push:/);
  expect(on).toContain("branches: [main]");
  expect(on).toContain("paths: ['supabase/migrations/*.sql']");
  expect(wf).toContain("if: github.event_name == 'pull_request' && contains(github.event.pull_request.labels.*.name, 'live-dry-run')");
});

test('s980: the gate runs the pre-flight against main and the live head before the dry run, and fails hard', () => {
  const gate = wf.slice(wf.indexOf('  dry-run:'), wf.indexOf('  rehearsal:'));
  expect(gate).toContain('scripts/ci/live-migration-head.sh');
  expect(gate).toContain('node scripts/ci/migration-preflight.mjs --base "$BASE_SHA" --live-head "$live"');
  expect(gate.indexOf('migration-preflight.mjs')).toBeLessThan(gate.indexOf('dry-run-migration.sh'));
  expect(gate).toContain('set -euo pipefail');
});

test('s980: the hand-started rehearsal is its own job, reports failures as warnings, and cannot pass the gate', () => {
  const reh = wf.slice(wf.indexOf('  rehearsal:'));
  expect(reh).toContain("if: github.event_name == 'workflow_dispatch'");
  expect(reh).toContain('REHEARSAL FAILED');
  expect(reh).toContain('::warning::');
  expect(fs.readFileSync('scripts/ci/auto-merge.sh', 'utf8')).toContain('select(.name == "dry-run" and .conclusion == "success")');
});

test('s980: a probe runs through EXECUTE in its own block and prints PROBE-ERROR instead of failing', () => {
  expect(run).toContain('begin execute \\$cf_probe\\$select (%s)::text\\$cf_probe\\$ into v;');
  expect(run).toContain("exception when others or query_canceled then v := 'PROBE-ERROR: ' || sqlerrm; end;");
});

test('s980: the pre-flight checks order, Decision 260 lines and transaction safety; the hook runs it', () => {
  for (const s of ['is not above the head', 'Replaces:', 'opens or ends its own transaction', 'CONCURRENTLY', "--live-head"]) expect(pre).toContain(s);
  expect(hook).toContain('node scripts/ci/migration-preflight.mjs --base origin/main');
  const out = execFileSync('node', ['scripts/ci/migration-preflight.mjs', '--base', 'HEAD'], { encoding: 'utf8' });
  expect(out).toContain('no new migrations');
});
