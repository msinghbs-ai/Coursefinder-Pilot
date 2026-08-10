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
  searchCourses: (query, limit = 50) => rpc('ui_search_courses', { p_query: query, p_limit: limit }),
}
