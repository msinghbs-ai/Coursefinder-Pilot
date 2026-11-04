import { supabase } from './lib/supabase'

// Dedicated role-checked bridges; the runner remains the existing governed API.
// Never call private security functions, query pipeline tables, or select courses in the browser.
export const intakeRunApi = {
  async read(view, args = {}) {
    const { data, error } = await supabase.rpc('admin_intake_run_read_v1', { p_view: view, p_args: args })
    if (error) throw error
    return data
  },
  async preview(scope, size, onProgress, sessionId, shouldPause = () => false) {
    const call = async (action, args) => {
      const { data, error } = await supabase.rpc('admin_intake_preview_v1', { p_action: action, p_args: args })
      if (error) throw error
      return data
    }
    let p = sessionId ? await call('read', { session_id: sessionId }) : await call('start', { scope, size })
    onProgress?.(p)
    while (!p.scan_complete) {
      if (shouldPause()) throw new Error('Preview paused. Use Resume preview to continue from the saved cursor.')
      p = await call('step', { session_id: p.session_id, page_no: p.page_no })
      onProgress?.(p)
    }
    return p
  },
  async prepare(args) {
    if (args.p_preview_token?.startsWith('page:')) {
      const { data, error } = await supabase.rpc('admin_intake_preview_prepare_v1', { p_session_id: args.p_preview_token.slice(5), p_reason: args.p_reason })
      if (error) throw error
      return data
    }
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
