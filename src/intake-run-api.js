import { supabase, adminRead } from './lib/supabase'

// Browser bridges below are integration dependencies, documented in docs/intake-run-validate.md.
// Never call private security functions, query pipeline tables, or select courses in the browser.
export const intakeRunApi = {
  read: (view, args = {}) => adminRead('intake_run_validate', { view, ...args }),
  async prepare(args) {
    const { data, error } = await supabase.rpc('admin_intake_cohort_prepare_v1', args)
    if (error) throw error
    return data
  },
  async run(cohortId, reason, key) {
    const { data, error } = await supabase.rpc('admin_job_run_now_v1', {
      p_job: 'intake-dates-apply', p_reason: reason,
      p_args: { cohort_id: cohortId, idempotency_key: key },
    })
    if (error) throw error
    return data
  },
}
