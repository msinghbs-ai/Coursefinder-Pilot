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
  if (!payload?.jobId) throw new Error('Layer 1 job was accepted without a Job ID')
  return payload
}

async function waitForLayer1Job(jobId, { intervalMs = 1500, timeoutMs = 180000 } = {}) {
  const started = Date.now()
  while (Date.now() - started < timeoutMs) {
    const job = await rpc('ui_layer1_job', { p_job_id: jobId })
    if (!job) throw new Error(`Layer 1 job not found: ${jobId}`)
    if (job.status === 'completed') return { ...job.result, jobId: job.jobId, jobStatus: job.status }
    if (job.status === 'failed') throw new Error(job.error || 'Layer 1 job failed')
    await new Promise(resolve => setTimeout(resolve, intervalMs))
  }
  throw new Error(`Layer 1 job is still running after ${Math.round(timeoutMs / 1000)} seconds. Check Jobs for status.`)
}

function courseDetail(courseId) {
  if (!courseId) throw new Error('Course detail requires a course ID')
  return rpc('ui_course_detail', { p_course_id: courseId })
}

export const api = {
  context: () => rpc('ui_context'),
  dashboard: () => rpc('ui_dashboard'),
  providers: (limit = 500) => rpc('ui_providers_list', { p_limit: limit }),
  campuses: (limit = 500) => rpc('ui_campuses_list', { p_limit: limit }),
  collections: (limit = 500) => rpc('ui_course_collections_list', { p_limit: limit }),
  courses: (limit = 1000) => rpc('ui_courses_list', { p_limit: limit }),
  courseDetail,
  scholarships: (limit = 500) => rpc('ui_scholarships_list', { p_limit: limit }),
  categories: (limit = 1000) => rpc('ui_categories_list', { p_limit: limit }),
  attributes: () => rpc('ui_attributes_list'),
  jobs: (limit = 500) => rpc('ui_jobs_list', { p_limit: limit }),
  reviews: (limit = 500) => rpc('ui_review_queue', { p_limit: limit }),
  regulatorySources: () => rpc('ui_regulatory_sources_list'),
  layer1Job: (jobId) => rpc('ui_layer1_job', { p_job_id: jobId }),
  latestLayer1Job: (country = 'AU') => rpc('ui_layer1_latest_job', { p_country_code: country }),
  runLayer1,
  waitForLayer1Job,
  searchCourses: (query, limit = 50) => rpc('ui_search_courses', { p_query: query, p_limit: limit }),
}
