import { createClient } from '@supabase/supabase-js'

// Public values, set as Cloudflare build variables. The portal holds only these two public values and no privileged key.
const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

export const configured = Boolean(url && key)

export const supabase = createClient(url || 'http://localhost', key || 'missing', {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
})

// The same read the Admin app uses for who is signed in and their role rank (public.admin_read 'context' -> public.ui_context()).
// Read only; roles are managed in Admin (Users and Roles), never here.
export async function readContext() {
  const { data, error } = await supabase.rpc('admin_read', { p_operation: 'context', p_args: {} })
  if (error) throw error
  return data
}
