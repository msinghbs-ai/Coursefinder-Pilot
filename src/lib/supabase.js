import { createClient, FunctionsHttpError } from '@supabase/supabase-js'

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
  if (error) {
    if (error instanceof FunctionsHttpError && error.context) {
      try {
        const payload = await error.context.clone().json()
        throw new Error(payload?.error || payload?.message || error.message || `${name} failed`)
      } catch (parseError) {
        if (parseError instanceof Error && parseError.message !== 'Unexpected end of JSON input') throw parseError
      }
    }
    throw new Error(error.message || `${name} failed`)
  }
  if (data?.error) throw new Error(data.error)
  return data
}

async function courses(limit = 1000) {
  const rows = await rpc('ui_courses_list', { p_limit: limit })
  return (rows || []).map(row => ({ ...row, id: row.id || row.course_id }))
}

export const api = {
  context: () => rpc('ui_context'),
  dashboard: () => rpc('ui_dashboard'),
  providers: (limit = 1000) => rpc('ui_providers_list', { p_limit: limit }),
  providerPage: ({ limit = 50, offset = 0, query = '', country = '', subdivision = '', lifecycle = '', publication = '', sort = 'provider', direction = 'asc' } = {}) => rpc('ui_providers_page', {
    p_limit: limit,
    p_offset: offset,
    p_query: query || null,
    p_country_code: country || null,
    p_subdivision_code: subdivision || null,
    p_lifecycle_status: lifecycle || null,
    p_publication_status: publication || null,
    p_sort: sort,
    p_direction: direction,
  }),
  providerDetail: providerId => rpc('ui_provider_detail', { p_provider_id: providerId }),
  campuses: (limit = 1000) => rpc('ui_campuses_list', { p_limit: limit }),
  collections: (limit = 1000) => rpc('ui_course_collections_list', { p_limit: limit }),
  courses,
  courseDetail: courseId => rpc('ui_course_detail', { p_course_id: courseId }),
  scholarships: (limit = 1000) => rpc('ui_scholarships_list', { p_limit: limit }),
  scholarshipDetail: scholarshipId => rpc('ui_scholarship_detail', { p_scholarship_id: scholarshipId }),
  categories: (limit = 1000) => rpc('ui_categories_list', { p_limit: limit }),
  attributes: () => rpc('ui_attributes_list'),
  attributeFamilies: () => rpc('ui_attribute_families_list'),
  attributeGroups: () => rpc('ui_attribute_groups_list'),
  attributeOptions: (limit = 5000) => rpc('ui_attribute_options_list', { p_limit: limit }),
  completenessProfiles: () => rpc('ui_completeness_profiles_list'),
  completenessCourses: (limit = 5000) => rpc('ui_course_completeness_list', { p_limit: limit }),
  evidence: (limit = 2000) => rpc('ui_evidence_governance_list', { p_limit: limit }),
  jobs: (limit = 500) => rpc('ui_jobs_list', { p_limit: limit }),
  reviews: (limit = 500) => rpc('ui_review_queue', { p_limit: limit }),
  regulatorySources: () => rpc('ui_regulatory_sources_list'),
  layer1Job: jobId => rpc('ui_layer1_job', { p_job_id: jobId }),
  latestLayer1Job: (country = 'AU') => rpc('ui_layer1_latest_job', { p_country_code: country }),
  runLayer1: ({ country = 'AU', apply = false, batchSize = 2500, offset = 0 } = {}) => invoke(country === 'CA' ? 'layer1-ca-live' : 'layer1-register-etl', { country, apply, batchSize, offset }),
  runLayer2AStatsCan: ({ apply = false, sampleRows = 1000 } = {}) => invoke('statcan-ca-psis-etl', { apply, sampleRows }),
  resetDatabase: () => invoke('pilot-reset', { confirm: 'RESET DATABASE' }),
  searchCourses: (query, limit = 50) => rpc('ui_search_courses', { p_query: query, p_limit: limit }),
}
