import { createClient } from '@supabase/supabase-js'

export function serviceClient(env) {
  if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) throw new Error('Layer 1 runtime is not configured')
  return createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
}

export async function rpc(client, name, args = {}) {
  const { data, error } = await client.rpc(name, args)
  if (error) throw new Error(`${name}: ${error.message}`)
  return data
}

export async function safeRpc(client, name, args = {}) {
  try { return await rpc(client, name, args) } catch { return null }
}
