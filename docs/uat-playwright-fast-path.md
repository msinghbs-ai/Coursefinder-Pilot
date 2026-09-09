# Playwright UAT fast path

The active Playwright suite remains under `tests/uat/`. Performance optimisation is configuration/orchestration-only; existing UAT test files and assertions are not rewritten by this change.

## Authentication cache

For deployed UAT, set `UAT_BASE_URL`, `UAT_EMAIL` (or `UAT_USERNAME`), and `UAT_PASSWORD`. `global-setup.mjs` signs in once, writes `storageState.json`, and Playwright reuses that authenticated browser state for the run.

Optional login-surface overrides are available when an environment uses different controls:

- `UAT_LOGIN_PATH` (default `/`)
- `UAT_USERNAME_SELECTOR` (default `#username, input[type="email"]`)
- `UAT_PASSWORD_SELECTOR` (default `#password, input[type="password"]`)
- `UAT_SUBMIT_SELECTOR` (default is the accessible `Sign in` button)

`storageState.json` is ignored by Git and must never be committed because it can contain authenticated session state.

## Smoke tagging

When a future or separately governed test is intentionally designated as smoke coverage, include the tag in its title, for example:

```js
test('provider catalogue opens @smoke', async ({ page }) => {
  // existing governed assertions
})
```

Run only smoke-tagged tests with:

```bash
npx playwright test --grep "@smoke"
```

The command is opt-in: it does not automatically retag, rewrite, move, combine, or change assertions in existing UAT tests.
