// Guards: StudySearch Feature Acceptance F-INT.05 (permission denial, slow timeout, duplicate run) under IQ-00313; the Run Now error words never claim a job did or did not start beyond what is known.
import { test, expect } from '@playwright/test'
import { intakeErrorMessage } from '../../src/intake-error-message.js'

const RUN = 'Running intake job', PREVIEW = 'Previewing eligible courses'

test('a Run Now permission refusal says the request started no job and points at Recover and Verify', () => {
  for (const e of [{ code: '42501', message: 'permission denied for function admin_intake_run_now_v1' }, { status: 403, message: 'x' }, { message: 'JWT expired' }]) {
    const m = intakeErrorMessage(RUN, e)
    expect(m).toContain('refused'); expect(m).toContain('did not start a job'); expect(m).toContain('Recover same request')
  }
})
test('a Run Now timeout says the outcome is unknown and that recovery cannot start a second job', () => {
  for (const e of [{ code: '57014', message: 'canceling statement due to statement timeout' }, { message: 'Gateway Time-out' }, { message: 'request timed out' }]) {
    const m = intakeErrorMessage(RUN, e)
    expect(m).toContain('outcome is not known'); expect(m).toContain('cannot start a second job'); expect(m).not.toContain('No intake job was started')
  }
})
test('a preview timeout still says no job was started', () => {
  expect(intakeErrorMessage(PREVIEW, { code: '57014', message: 'statement timeout' })).toContain('No intake job was started.')
})
test('other stages: permission refusal says nothing was changed; unknown errors keep the server wording; empty errors get the default', () => {
  expect(intakeErrorMessage('Loading capabilities', { code: '42501', message: 'permission denied' })).toContain('Nothing was changed')
  expect(intakeErrorMessage(RUN, new Error('Network interrupted'))).toBe('Network interrupted')
  expect(intakeErrorMessage(RUN, undefined)).toBe('Request failed. Check access and refresh before continuing.')
  expect(intakeErrorMessage(PREVIEW, { message: 'permission denied' })).toContain('Nothing was changed')
})
