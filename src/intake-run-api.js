import { supabase } from './lib/supabase'

// Dedicated role-checked bridges; the runner remains the existing governed API.
// Never call private security functions, query pipeline tables, or select courses in the browser.
export const intakeRunApi = {
  async read(view, args = {}) {
    const { data, error } = await supabase.rpc('admin_intake_run_read_v1', { p_view: view, p_args: args })
    if (error) throw error
    return data
  },
  async prepare(args) {
    const { data, error } = await supabase.rpc('admin_intake_cohort_prepare_v1', args)
    if (error) throw error
    return data
  },
  async run(cohortId) {
    const { data, error } = await supabase.rpc('admin_intake_run_now_v1', { p_cohort_id: cohortId })
    if (error) throw error
    return data
  },
}
