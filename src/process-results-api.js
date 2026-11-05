import { supabase } from './lib/supabase'

// CF-247 process accountability (Platform Admin decision 5 Nov 2026 §6): one role-checked bridge over saved results only
// (public.admin_process_results_v1). The browser never queries pipeline tables or computes counts itself.
// Automation Progress (decision 5 Nov 2026 16:36 §3-§5): public.admin_intake_progress_v1, read only. Pause/Resume (§4) is the existing
// Automations control public.admin_automation_control (role-checked and audited there); no other write is reachable from this screen.
export const processResultsApi = {
  async read(view, args = {}) {
    const { data, error } = await supabase.rpc('admin_process_results_v1', { p_view: view, p_args: args })
    if (error) throw error
    return data
  },
  async progress(view, args = {}) {
    const { data, error } = await supabase.rpc('admin_intake_progress_v1', { p_view: view, p_args: args })
    if (error) throw error
    return data
  },
  async control(job, action, args = {}) {
    if (!['pause', 'resume'].includes(action)) throw new Error('Only Pause and Resume are available here')
    const { data, error } = await supabase.rpc('admin_automation_control', { p_job: job, p_action: action, p_args: args })
    if (error) throw error
    return data
  },
}
