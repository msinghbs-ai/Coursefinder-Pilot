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
  // CF-247 (Platform Admin 16 Nov 2026 22:12): an invitation carries the person's name; the server adds the role, the guide address and the
  // admin sign-in address (redirectTo) for the Supabase email template
  create: ({ email, mode = 'invite', password = '', roles = [], expiresAt = null, fullName = '' }) => invoke({
    action: 'create', email, mode, password: mode === 'password' ? password : undefined,
    roles, expires_at: expiresAt, full_name: mode === 'invite' ? fullName : undefined,
  }),
  // CF-247 (Platform Admin 16 Nov 2026 22:12): a password reset email to another person's account (not a Platform Admin); the link returns to the admin sign-in
  resetPassword: (userId) => invoke({ action: 'reset_password', user_id: userId }),
  replaceRoles: ({ userId, roles = [], expiresAt = null }) => invoke({
    action: 'roles', user_id: userId, roles, expires_at: expiresAt,
  }),
  setDisabled: (userId, disabled) => invoke({ action: disabled ? 'disable' : 'enable', user_id: userId }),
  // 16 Oct 2026: Platform Admin only; Platform Admins, your own account and the system account cannot be deleted (checked in the database)
  deleteUser: (userId) => invoke({ action: 'delete', user_id: userId }),
}
