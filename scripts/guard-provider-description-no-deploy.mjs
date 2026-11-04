// The 4 Nov 2026 Provider Description mandate authorises a draft PR but no deployment.
// Workers Builds also listens to feature-branch pushes outside GitHub Actions.
// Refuse its build before Wrangler can upload this development branch. Main and
// local build/test commands continue through the normal build contract.
if (process.env.WORKERS_CI_BRANCH === 'codex/provider-description-autonomy') {
  throw new Error('Provider Description development hold: this branch is for review only. Claude controls deployment after Platform Admin release authorisation.')
}
