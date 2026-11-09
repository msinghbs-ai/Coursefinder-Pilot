// F-INT.05: plain words for a failed intake request, by stage. Pure and read-only: it only words an error
// the server or network already returned and never claims more than is known about whether a job started.
const text = e => String(e?.message || '')
const isTimeout = e => e?.code === '57014' || /statement timeout|timed? ?out|gateway time-?out|\b504\b/i.test(text(e))
const isDenied = e => e?.code === '42501' || e?.status === 401 || e?.status === 403 || /permission denied|not authori[sz]ed|insufficient privilege|jwt expired|row-level security|forbidden/i.test(text(e))

export function intakeErrorMessage(stage, e) {
  if (stage === 'Previewing eligible courses' && isTimeout(e))
    return 'Preview timed out before a cohort was fixed. No intake job was started. Ask the operator to check preview performance before trying again.'
  if (stage === 'Running intake job') {
    if (isDenied(e)) return 'Run Now was refused: your role or sign-in does not permit it. The server refused the request, so this request did not start a job. Sign in again or ask a Platform Admin for access, then use Recover same request or Verify catalogue & publication to confirm.'
    if (isTimeout(e)) return 'Run Now timed out and the outcome is not known: the job may or may not have started. Use Recover same request (it repeats the same request key, so it cannot start a second job) or Verify catalogue & publication before doing anything else.'
  }
  if (isDenied(e)) return 'Your role or sign-in does not permit this action. Nothing was changed. Sign in again or ask a Platform Admin for access.'
  return text(e) || 'Request failed. Check access and refresh before continuing.'
}
