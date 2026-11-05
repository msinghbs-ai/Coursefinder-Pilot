import { supabase } from './lib/supabase'

// CF-247 process accountability (Platform Admin decision 5 Nov 2026 §6): one role-checked bridge over saved results only
// (public.admin_process_results_v1). The browser never queries pipeline tables or computes counts itself.
export const processResultsApi = {
  async read(view, args = {}) {
    const { data, error } = await supabase.rpc('admin_process_results_v1', { p_view: view, p_args: args })
    if (error) throw error
    return data
  },
}
