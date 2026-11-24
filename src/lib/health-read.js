// The stored platform-health read, with no stylesheet attached (so the v1.1 screens can use it). PlatformHealth.jsx re-exports both names.
import { adminRead } from './supabase'

export function isHealthContract(h) { return Boolean(h && typeof h.overall === 'string' && Array.isArray(h.checks)) }
export async function readPlatformHealth() { try { const h = await adminRead('platform_health', {}); return isHealthContract(h) ? h : null } catch { return null } }
