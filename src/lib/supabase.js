import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

if (!url || !key) console.warn('Missing VITE_SUPABASE_URL or VITE_SUPABASE_PUBLISHABLE_KEY')

export const supabase = createClient(url ?? '', key ?? '', {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
})

async function rpc(name, args = {}) {
  const { data, error } = await supabase.rpc(name, args)
  if (error) throw error
  return data
}

async function runLayer1({ country = 'AU', apply = false, maxRecords = 100 } = {}) {
  const { data: sessionData, error: sessionError } = await supabase.auth.getSession()
  if (sessionError) throw sessionError
  const token = sessionData?.session?.access_token
  if (!token) throw new Error('No authenticated session')

  const response = await fetch('/api/layer1/run', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ country, apply, maxRecords }),
  })
  const payload = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(payload?.error || `Layer 1 run failed: ${response.status}`)
  return payload
}

export const api = {
  context: () => rpc('ui_context'),
  dashboard: () => rpc('ui_dashboard'),
  providers: (limit = 500) => rpc('ui_providers_list', { p_limit: limit }),
  campuses: (limit = 500) => rpc('ui_campuses_list', { p_limit: limit }),
  collections: (limit = 500) => rpc('ui_course_collections_list', { p_limit: limit }),
  courses: (limit = 1000) => rpc('ui_courses_list', { p_limit: limit }),
  courseDetail: (courseId) => rpc('ui_course_detail', { p_course_id: courseId }),
  scholarships: (limit = 500) => rpc('ui_scholarships_list', { p_limit: limit }),
  categories: (limit = 1000) => rpc('ui_categories_list', { p_limit: limit }),
  attributes: () => rpc('ui_attributes_list'),
  jobs: (limit = 500) => rpc('ui_jobs_list', { p_limit: limit }),
  reviews: (limit = 500) => rpc('ui_review_queue', { p_limit: limit }),
  regulatorySources: () => rpc('ui_regulatory_sources_list'),
  runLayer1,
  searchCourses: (query, limit = 50) => rpc('ui_search_courses', { p_query: query, p_limit: limit }),
}
