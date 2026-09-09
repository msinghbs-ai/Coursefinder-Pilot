# Playwright UAT authentication cache and smoke fast path

The active UAT suite remains under `tests/uat/`. This optimisation is configuration- and orchestration-only: existing UAT test files, assertions, and browser data-access behaviour are not rewritten.

## Authentication cache

For deployed UAT, provide credentials only through environment variables:

- `UAT_BASE_URL` — deployed UAT base URL.
- `UAT_USERNAME` — UAT username. `UAT_EMAIL` is accepted as a compatibility fallback.
- `UAT_PASSWORD` — UAT password.
- `UAT_LOGIN_PATH` — optional login path; defaults to `/`.
- `UAT_USERNAME_SELECTOR` — optional login control override; defaults to `#username`.
- `UAT_PASSWORD_SELECTOR` — optional password control override; defaults to `#password`.
- `UAT_SUBMIT_SELECTOR` — optional submit-control override; otherwise the accessible `Sign in` button is used.

`global-setup.ts` authenticates once and writes `storageState.json`. Playwright then reuses that state for the run. `storageState.json` is git-ignored because it may contain authenticated session material and must never be committed.

If `UAT_BASE_URL` is not set, global setup writes an empty anonymous storage state so local contract/browser UAT can continue using the same configuration without embedded credentials.

## Smoke tagging

For future tests that are separately approved for smoke coverage, add `@smoke` to the test title:

```ts
test('provider catalogue opens @smoke', async ({ page }) => {
  await page.goto('/providers')
})
```

Run only smoke-tagged coverage with:

```bash
npx playwright test --grep "@smoke"
```

This command is opt-in and does not retag, rewrite, move, combine, or alter assertions in existing UAT tests.
