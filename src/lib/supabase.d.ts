import type { SupabaseClient } from '@supabase/supabase-js'
import type { AdminReadOperation, AdminReadPayload } from '../types/admin-read'
import type { CourseFinderApi } from '../types/api'

export const supabase: SupabaseClient
export const api: CourseFinderApi
export function adminRead<T extends AdminReadOperation>(operation: T, args?: Record<string, unknown>): Promise<AdminReadPayload<T>>
