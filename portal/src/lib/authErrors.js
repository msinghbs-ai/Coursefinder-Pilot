// Turns a Supabase Auth error into words a counsellor can act on. A wrong password and a set-up fault must never look the same:
// the first is theirs to fix, the second belongs to a Platform Admin.
export function explainAuthError(error, key = { kind: 'unknown', length: 0 }) {
  const status = Number(error?.status || 0)
  const code = String(error?.code || '')
  const text = String(error?.message || '')
  if (code === 'email_not_confirmed' || /email not confirmed/i.test(text)) {
    return { kind: 'unconfirmed', text: 'This email address has not been confirmed yet. Use the link in the invitation email, or ask a Platform Admin to confirm it.' }
  }
  if (status === 429 || code === 'over_request_rate_limit' || /rate limit/i.test(text)) {
    return { kind: 'rate', text: 'Too many attempts in a short time. Wait a minute, then try again.' }
  }
  if (status === 401 || status === 403 || /api key|apikey|invalid jwt|no api key/i.test(text)) {
    const detail = key.kind && key.kind !== 'unknown' ? ` (connection key: ${key.kind}, ${key.length} characters)` : ''
    return { kind: 'setup', text: `The portal could not connect to StudySearch because its connection key was refused. Your email and password were not checked. Tell a Platform Admin${detail}.` }
  }
  if (status === 0 || /failed to fetch|networkerror|load failed|retryable/i.test(text) || error?.name === 'AuthRetryableFetchError') {
    return { kind: 'network', text: 'The portal could not reach StudySearch. Check your internet connection and try again.' }
  }
  if (status === 400 || code === 'invalid_credentials' || /invalid login credentials/i.test(text)) {
    return { kind: 'credentials', text: 'That email and password did not match. Please try again, or use "Forgot your password?".' }
  }
  return { kind: 'other', text: 'Sign-in did not work. Please try again in a moment.' }
}
