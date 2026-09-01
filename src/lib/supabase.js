import { createClient, FunctionsHttpError } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

if (!url || !key) console.warn('Missing VITE_SUPABASE_URL or VITE_SUPABASE_PUBLISHABLE_KEY')

export const supabase = createClient(url ?? '', key ?? '', {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
})

let activeCoursePageRead = null

/**
 * Governed browser read boundary.
 *
 * Browser code must not execute legacy public.ui_* RPCs directly. All reads enter
 * through public.admin_read, which is SECURITY INVOKER and delegates to private,
 * server-side role-checked implementations.
 */
async function adminRead(operation, args = {}) {
  // CF-060: Jobs/Sources are canonical shell workspaces again.
  // Never manufacture empty operational results based on the current hash route.

  // M2.4.0: the first Courses render and its large filter catalogue used to hit
  // admin_read concurrently. Preserve both exact governed reads, but allow the
  // operator-visible page request to complete before filter metadata competes for
  // the same database/API capacity. Subsequent filter refreshes remain exact.
  if (operation === 'course_filters' && activeCoursePageRead) {
    try { await activeCoursePageRead } catch { /* page caller owns its error */ }
  }

  const runRead = async () => {
    const { data, error, status } = await supabase.rpc('admin_read', {
      p_operation: operation,
      p_args: args ?? {},
    })
    return { data, error, status: Number(status || 0) }
  }

  const execute = async () => {
    const attempts = operation === 'evidence_detail' ? 3 : 1
    let lastError = null
    for (let attempt = 1; attempt <= attempts; attempt++) {
      const { data, error, status } = await runRead()
      if (!error) return data
      lastError = error
      const transientServerFailure = status >= 500 && status <= 599
      if (!transientServerFailure || attempt === attempts) throw error
      await new Promise(resolve => setTimeout(resolve, attempt === 1 ? 180 : 420))
    }
    throw lastError
  }

  const request = execute()

  if (operation === 'courses_page') {
    activeCoursePageRead = request
    try { return await request } finally { if (activeCoursePageRead === request) activeCoursePageRead = null }
  }
  return request
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

const pageItems = value => value?.items ?? value?.rows ?? (Array.isArray(value) ? value : [])
const bounded = (value, fallback = 50) => Math.min(Math.max(Number(value) || fallback, 1), 200)
const present = value => value === '' || value === null || value === undefined ? null : value

async function entityPage(operation, args = {}) {
  return adminRead(operation, {
    limit: bounded(args.limit, 50),
    offset: Math.max(Number(args.offset) || 0, 0),
    query: args.query || null,
    country_code: args.country || args.country_code || null,
    subdivision_code: args.subdivision || args.subdivision_code || null,
    provider_id: args.provider || args.provider_id || null,
    level_code: args.level || args.level_code || null,
    field_code: args.field || args.field_code || null,
    delivery_mode: args.delivery || args.delivery_mode || null,
    lifecycle_status: args.lifecycle || args.lifecycle_status || null,
    publication_status: args.publication || args.publication_status || null,
    status: args.status || null,
    has_fee: args.hasFee ?? args.has_fee ?? null,
    has_intake: args.hasIntake ?? args.has_intake ?? null,
    has_english: args.hasEnglish ?? args.has_english ?? null,
    has_scholarship: args.hasScholarship ?? args.has_scholarship ?? null,
    has_state: args.hasState ?? args.has_state ?? null,
    has_link: args.hasLink ?? args.has_link ?? null,
    min_completeness: args.minCompleteness === '' ? null : (args.minCompleteness ?? args.min_completeness ?? null),
    freshness: args.freshness || null,
    sort: args.sort || null,
    direction: args.direction || 'asc',
  })
}

async function providerRelated(providerId, key, { limit = 25, offset = 0 } = {}) {
  const detail = await adminRead('provider_detail', { id: providerId })
  const container = detail?.[key]
  const all = container?.items ?? container?.rows ?? (Array.isArray(container) ? container : [])
  const start = Math.max(Number(offset) || 0, 0)
  const size = bounded(limit, 25)
  const items = all.slice(start, start + size)
  const total = Number(detail?.[`related_${key === 'courses' ? 'course' : 'evidence'}_total`] ?? container?.total ?? all.length)
  return { items, rows: items, total, limit: size, offset: start }
}

async function attributesBundle(limit = 200) {
  return adminRead('attributes', { limit: bounded(limit, 200) })
}

export const api = {
  context: () => adminRead('context'),
  dashboard: () => adminRead('dashboard'),

  providers: async (limit = 200) => pageItems(await entityPage('providers_page', { limit })),
  providerPage: args => entityPage('providers_page', args),
  providerFilterOptions: (country = '') => adminRead('provider_filters', { country_code: country || null }),
  providerDetail: providerId => adminRead('provider_detail', { id: providerId }),
  providerRelatedCourses: args => providerRelated(args.providerId, 'courses', args),
  providerRelatedEvidence: args => providerRelated(args.providerId, 'evidence', args),

  campuses: async (limit = 200) => pageItems(await entityPage('campuses_page', { limit })),
  collections: async () => [],

  courses: async (limit = 200) => pageItems(await entityPage('courses_page', { limit })),
  coursePage: args => entityPage('courses_page', args),
  courseFilterOptions: ({ country = '', subdivision = '' } = {}) => adminRead('course_filters', {
    country_code: country || null,
    subdivision_code: subdivision || null,
  }),
  catalogueFilterPage: ({ kind, country = '', subdivision = '', query = '', limit = 10, offset = 0 } = {}) => adminRead('catalogue_filter_page', {
    filter_kind: kind,
    country_code: country || null,
    subdivision_code: subdivision || null,
    query: query || null,
    limit: Math.min(Math.max(Number(limit)||10,1),10),
    offset: Math.max(Number(offset)||0,0),
  }),
  courseDetail: courseId => adminRead('course_detail', { id: courseId }),
  courseRelatedCampuses: async courseId => {
    const detail = await adminRead('course_detail', { id: courseId })
    return detail?.campuses ?? detail?.related_campuses ?? []
  },

  scholarships: async (limit = 200) => pageItems(await entityPage('scholarships_page', { limit })),
  scholarshipPage: args => entityPage('scholarships_page', args),
  scholarshipDetail: scholarshipId => adminRead('scholarship_detail', { id: scholarshipId }),

  qiltPage: ({ limit = 50, offset = 0, query = '', survey = '', metric = '', provider = '', status = '', year = '', sort = 'provider', direction = 'asc' } = {}) =>
    adminRead('qilt_outcomes', {
      limit: bounded(limit, 50), offset: Math.max(Number(offset) || 0, 0), query: query || null,
      survey_code: survey || null, metric_code: metric || null, provider_id: provider || null,
      status: status || null, year: year === '' ? null : Number(year), sort, direction,
    }),
  filterOptionPage: ({ kind, query = '', country = '', survey = '', limit = 10, offset = 0 } = {}) => adminRead('admin_filter_option_page', {
    kind,
    query: query || null,
    country_code: country || null,
    survey_code: survey || null,
    limit: Math.min(Math.max(Number(limit)||10,1),10),
    offset: Math.max(Number(offset)||0,0),
  }),
  qiltFilterOptions: (survey = '') => adminRead('qilt_filters', { survey_code: survey || null }),
  prismsPage: ({ limit = 50, offset = 0, query = '', subdivision = '', studyArea = '', sector = '', remoteness = '', suppressed = null, sort = 'geography', direction = 'asc' } = {}) =>
    adminRead('prisms_student_flow', {
      limit: bounded(limit, 50), offset: Math.max(Number(offset) || 0, 0), query: query || null,
      subdivision_code: subdivision || null, study_area_code: studyArea || null, sector_code: sector || null,
      remoteness_area: remoteness || null, suppressed, sort, direction,
    }),
  prismsFilterOptions: () => adminRead('prisms_filters'),

  evidencePage: ({
    limit = 50, offset = 0, query = '', country = '', sourceId = '', layer = '', entityType = '', entityId = '', providerId = '', jobId = '',
    evidenceType = '', mime = '', hash = '', jobStatus = '', status = '', extractionState = '', freshness = '', verifiedFrom = '', verifiedTo = '',
    unresolvedConflicts = '', sort = 'captured', direction = 'desc',
  } = {}) => adminRead('evidence_page', {
    limit: bounded(limit, 50), offset: Math.max(Number(offset) || 0, 0), query: query || null,
    country: country || null, source_id: sourceId || null, layer: layer || null, entity_type: entityType || null,
    entity_id: entityId || null, provider_id: providerId || null, job_id: jobId || null,
    evidence_type: evidenceType || null, mime: mime || null, hash: hash || null, job_status: jobStatus || null,
    status: status || null, extraction_state: extractionState || null, freshness: freshness || null,
    verified_from: verifiedFrom || null, verified_to: verifiedTo || null,
    ...(unresolvedConflicts === '' || unresolvedConflicts === null || unresolvedConflicts === undefined ? {} : { unresolved_conflicts: unresolvedConflicts === true || unresolvedConflicts === 'true' }),
    sort, direction,
  }),
  evidenceFilterOptions: () => adminRead('evidence_filters'),
  evidenceDetail: evidenceId => adminRead('evidence_detail', { id: evidenceId }),
  evidenceObservations: (evidenceId, { limit = 100, offset = 0, entityType = '' } = {}) => adminRead('evidence_observations', {
    id: evidenceId, limit: bounded(limit, 100), offset: Math.max(Number(offset) || 0, 0), entity_type: entityType || null,
  }),
  evidenceEntities: (evidenceId, { limit = 100, offset = 0, entityType = '' } = {}) => adminRead('evidence_entities', {
    id: evidenceId, limit: bounded(limit, 100), offset: Math.max(Number(offset) || 0, 0), entity_type: entityType || null,
  }),
  evidenceAccess: (evidenceId, mode = 'preview') => invoke('admin-evidence-access', {
    evidence_id: evidenceId,
    mode: mode === 'download' ? 'download' : 'preview',
  }),

  reviewsPage: ({ limit = 50, offset = 0, query = '', domain = '', status = '', sort = 'priority', direction = 'desc' } = {}) =>
    adminRead('reviews_page', {
      limit: bounded(limit, 50), offset: Math.max(Number(offset) || 0, 0), query: query || null,
      domain: domain || null, status: status || null, sort, direction,
    }),
  reviewFilterOptions: async () => ({ domains: [], statuses: [] }),

  categories: async () => [],
  attributes: async () => (await attributesBundle())?.attributes ?? [],
  attributeFamilies: async () => (await attributesBundle())?.families ?? [],
  attributeGroups: async () => (await attributesBundle())?.groups ?? [],
  attributeOptions: async (limit = 200) => (await attributesBundle(limit))?.options ?? [],
  completenessProfiles: async () => (await attributesBundle())?.completeness_profiles ?? [],
  completenessCourses: async (limit = 200) => pageItems(await entityPage('courses_page', {
    limit: bounded(limit, 200), sort: 'completeness', direction: 'asc',
  })),

  evidence: async (limit = 200) => pageItems(await adminRead('evidence_page', { limit: bounded(limit, 200), offset: 0 })),
  jobs: (limit = 200) => adminRead('jobs', { limit: bounded(limit, 200) }),
  reviews: (limit = 200) => adminRead('reviews', { limit: bounded(limit, 200) }),
  regulatorySources: () => adminRead('sources'),

  layer1Job: jobId => adminRead('pipeline_job_detail', { id: jobId }),
  latestLayer1Job: async (country = 'AU') => {
    const result = await adminRead('pipeline_jobs_page', {
      limit: 50, offset: 0, country_code: country || null, sort: 'created', direction: 'desc',
    })
    return pageItems(result)[0] ?? null
  },

  runLayer1: ({ country = 'AU', apply = false, batchSize = 2500, offset = 0 } = {}) =>
    invoke(country === 'CA' ? 'layer1-ca-live' : 'layer1-register-etl', { country, apply, batchSize, offset }),
  runLayer2AStatsCan: ({ apply = false, sampleRows = 1000 } = {}) =>
    invoke('statcan-ca-psis-etl', { apply, sampleRows }),
  resetDatabase: () => invoke('pilot-reset', { confirm: 'RESET DATABASE' }),

  searchCourses: async (query, limit = 50) => pageItems(await entityPage('courses_page', {
    query, limit: bounded(limit, 50), sort: 'course', direction: 'asc',
  })),
}

export { adminRead }