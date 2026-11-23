// Guards: Platform Admin 24 Nov 2026 06:15 AEDT (UI-UX plan v1.2 section 6, CI efficiency and gate integrity: no label starts, cancels or adds a placeholder check to Test evidence; Provider description isolated acceptance stays, path-filtered to its inputs; no gate weakened)
// s1018: test-evidence.yml has no labeled trigger and a push still cancels the older run; test-evidence-label.yml starts Test evidence by
// workflow_dispatch for full-suite-evidence only; provider-description-integration.yml runs on pull requests to main that change its inputs.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = (p) => fs.readFileSync(p, 'utf8')

test('s1018: Test evidence runs on opened, synchronize, reopened and ready_for_review only; a push still cancels the older run', () => {
  const wf = read('.github/workflows/test-evidence.yml')
  expect(wf).toContain('  pull_request:\n    types: [opened, synchronize, reopened, ready_for_review]\n  workflow_dispatch:')
  expect(wf).not.toMatch(/types: \[[^\]]*labeled/)
  expect(wf).toContain('  group: test-evidence-${{ github.event.pull_request.number || inputs.pr }}\n  cancel-in-progress: true')
  expect(wf).toContain('needs: [test-evidence-plan, test-evidence-shard]')
})

test('s1018: the full-suite-evidence label starts Test evidence by workflow_dispatch; any other label touches nothing', () => {
  const wf = read('.github/workflows/test-evidence-label.yml')
  expect(wf).toContain('  pull_request:\n    types: [labeled]')
  expect(wf).toContain('  cancel-in-progress: false')
  expect(wf).toContain("if: github.event.label.name == 'full-suite-evidence' && github.event.pull_request.head.repo.full_name == github.repository")
  expect(wf).toContain('run: gh workflow run test-evidence.yml --repo "$GITHUB_REPOSITORY" --ref "$HEAD_REF" -f pr="$PR"')
  expect((wf.match(/^  [a-z-]+:\n    if:/gm) || []).length).toBe(1)
  expect(wf).toContain('permissions:\n  contents: read\n  actions: write')
})

test('s1018: Provider description isolated acceptance stays, on pull requests to main that change its inputs', () => {
  const wf = read('.github/workflows/provider-description-integration.yml')
  expect(wf).toContain('  pull_request:\n    branches: [main]\n    paths:')
  for (const p of ['.github/workflows/provider-description-integration.yml', 'supabase/functions/coverage-sweep/**', 'supabase/migrations-archive/**',
    'supabase/migrations/*pdesc*', 'supabase/migrations/*prompt*', 'tests/fixtures/p1-provider-descriptions/**', 'tests/fixtures/pdesc-*/**',
    'tests/fixtures/provider-description-autonomy/**', 'tests/uat/*pdesc*', 'tests/uat/*provider-description*', 'src/ProviderDescriptionPrompt.jsx',
    'src/provider-description-run-api.js']) expect(wf).toContain(`      - '${p}'`)
  expect(wf).toContain('  workflow_dispatch:')
  // every fixture the job replays is under a filtered path
  for (const f of wf.match(/bash tests\/fixtures\/[a-z0-9-]+\/run\.sh/g) || []) expect(f).toMatch(/tests\/fixtures\/(pdesc-[a-z0-9-]+|provider-description-autonomy)\/run\.sh/)
})
