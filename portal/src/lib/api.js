import { supabase } from './supabase.js'
import { ApiError, toApiError } from './apiErrors.js'

export { ApiError, toApiError }

export async function rpc(name, args) {
  const { data, error } = args === undefined ? await supabase.rpc(name) : await supabase.rpc(name, args)
  if (error) throw toApiError(error)
  return data
}
