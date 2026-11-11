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

// CF-247 F-PDESC (11 Nov 2026): Fill description (on demand) and whether the prompt from Settings is in use. Kept here so the panel reaches
// the database through this one module, as before.
export const providerDescriptionFillApi = {
  async promptOn() {
    const { data, error } = await supabase.rpc('admin_provider_description_prompt_v1', { p_action: 'read', p_args: {} })
    if (error) throw error
    return data?.prompt_on === true
  },
  async fill(providerIds) {
    const { data, error } = await supabase.rpc('admin_provider_description_fill_v1', { p_provider_ids: providerIds })
    if (error) throw error
    return data || {}
  },
}
