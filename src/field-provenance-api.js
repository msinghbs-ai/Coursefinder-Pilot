// CF-247 s812: the two Inbox-dispatcher calls (field locks read, primary campus preview and apply). Kept apart from field-provenance.js so that file stays pure.
import { supabase } from './lib/supabase'

export const fieldProvenanceApi = {
  async read(entity, id) {
    const { data, error } = await supabase.rpc('admin_layer4_inbox', { p_action: 'field_provenance', p_args: { entity, id } })
    if (error) throw error
    return data || {}
  },
}

export const bulkPrimaryApi = {
  async call(action, args) {
    const { data, error } = await supabase.rpc('admin_layer4_inbox', { p_action: action, p_args: args })
    if (error) throw error
    if (!data || typeof data !== 'object') throw new Error('The primary campus service returned no result.')
    return data
  },
}
