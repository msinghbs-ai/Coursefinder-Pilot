// CF-247 provider description autonomy mandate (4 November 2026).
// The server fixes cohort membership, checks authority and owns idempotency.
import { supabase } from './lib/supabase'

export const providerDescriptionRunApi = {
  async call(action, args = {}) {
    const { data, error } = await supabase.rpc('admin_provider_description_run_v1', { p_action: action, p_args: args })
    if (error) throw error
    if (!data || typeof data !== 'object') throw new Error('The provider description service returned no saved result.')
    return data
  },
}
