import { FunctionsHttpError } from '@supabase/supabase-js'
import { supabase } from './lib/supabase'

async function invoke(body) {
  const { data, error } = await supabase.functions.invoke('admin-user-management', { body })
  if (error) {
    if (error instanceof FunctionsHttpError && error.context) {
      try {
        const payload = await error.context.clone().json()
        throw new Error(payload?.error || payload?.message || error.message || 'Admin user management failed')
      } catch (parseError) {
        if (parseError instanceof Error && parseError.message !== 'Unexpected end of JSON input') throw parseError
      }
    }
    throw new Error(error.message || 'Admin user management failed')
  }
  if (data?.error) throw new Error(data.error)
  return data
}

export const accessApi = {
  list: () => invoke({ action: 'list' }),
  create: ({ email, mode = 'invite', password = '', roles = [], expiresAt = null }) => invoke({
    action: 'create', email, mode, password: mode === 'password' ? password : undefined,
    roles, expires_at: expiresAt,
  }),
  replaceRoles: ({ userId, roles = [], expiresAt = null }) => invoke({
    action: 'roles', user_id: userId, roles, expires_at: expiresAt,
  }),
  setDisabled: (userId, disabled) => invoke({ action: disabled ? 'disable' : 'enable', user_id: userId }),
}
