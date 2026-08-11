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

async function invoke(name, body) {
  const { data, error } = await supabase.functions.invoke(name, { body })
  if (error) throw new Error(error.message || `${name} failed`)
  if (data?.error) throw new Error(data.error)
  return data
}

function courseDetail(courseId) {
  if (!courseId) throw new Error('Course detail requires a course ID')
  return rpc('ui_course_detail', { p_course_id: courseId })
}

async function courses(limit = 1000) {
  const rows = await rpc('ui_courses_list', { p_limit: limit })
  return (rows || []).map(row => ({ ...row, id: row.id || row.course_id }))
}

export const api = {
  context: () => rpc('ui_context'),
  dashboard: () => rpc('ui_dashboard'),
  providers: (limit = 500) => rpc('ui_providers_list', { p_limit: limit }),
  campuses: (limit = 500) => rpc('ui_campuses_list', { p_limit: limit }),
  collections: (limit = 500) => rpc('ui_course_collections_list', { p_limit: limit }),
  courses,
  courseDetail,
  scholarships: (limit = 500) => rpc('ui_scholarships_list', { p_limit: limit }),
  categories: (limit = 1000) => rpc('ui_categories_list', { p_limit: limit }),
  attributes: () => rpc('ui_attributes_list'),
  jobs: (limit = 500) => rpc('ui_jobs_list', { p_limit: limit }),
  reviews: (limit = 500) => rpc('ui_review_queue', { p_limit: limit }),
  regulatorySources: () => rpc('ui_regulatory_sources_list'),
  layer1Job: (jobId) => rpc('ui_layer1_job', { p_job_id: jobId }),
  latestLayer1Job: (country = 'AU') => rpc('ui_layer1_latest_job', { p_country_code: country }),
  runLayer1: ({ country = 'AU', apply = false, batchSize = 2500, offset = 0 } = {}) => invoke('layer1-register-etl', {
    country,
    apply,
    batchSize,
    offset,
  }),
  resetDatabase: () => invoke('pilot-reset', { confirm: 'RESET DATABASE' }),
  searchCourses: (query, limit = 50) => rpc('ui_search_courses', { p_query: query, p_limit: limit }),
}
