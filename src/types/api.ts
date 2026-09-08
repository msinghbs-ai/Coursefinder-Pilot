import type { SupabaseClient } from '@supabase/supabase-js'
import type { AdminReadOperation, AdminReadPayload, CourseDetailPayload, PagePayload, ProviderDetailPayload, ScholarshipDetailPayload } from './admin-read'
import type { Campus, Course, Evidence, Provider, Scholarship } from './entities'
import type { Attribute, AttributeFamily, AttributeGroup, AttributeOption, CompletenessProfile } from './pim'

export interface EntityPageArgs {
  limit?: number
  offset?: number
  query?: string
  country?: string
  country_code?: string
  subdivision?: string
  subdivision_code?: string
  provider?: string
  provider_id?: string
  level?: string
  level_code?: string
  field?: string
  field_code?: string
  delivery?: string
  delivery_mode?: string
  lifecycle?: string
  lifecycle_status?: string
  publication?: string
  publication_status?: string
  status?: string
  sort?: string
  direction?: string
  [key: string]: unknown
}

export interface CourseFinderApi {
  context(): Promise<unknown>
  dashboard(): Promise<unknown>
  providers(limit?: number): Promise<Provider[]>
  providerPage(args?: EntityPageArgs): Promise<PagePayload<Provider>>
  providerFilterOptions(country?: string): Promise<unknown>
  providerDetail(providerId: string): Promise<ProviderDetailPayload>
  providerRelatedCourses(args: EntityPageArgs & { providerId: string }): Promise<PagePayload<Course>>
  providerRelatedEvidence(args: EntityPageArgs & { providerId: string }): Promise<PagePayload<Evidence>>
  campuses(limit?: number): Promise<Campus[]>
  collections(): Promise<unknown[]>
  courses(limit?: number): Promise<Course[]>
  coursePage(args?: EntityPageArgs): Promise<PagePayload<Course>>
  courseFilterOptions(args?: { country?: string; subdivision?: string }): Promise<unknown>
  catalogueFilterPage(args?: Record<string, unknown>): Promise<unknown>
  courseDetail(courseId: string): Promise<CourseDetailPayload>
  courseRelatedCampuses(courseId: string): Promise<Campus[]>
  scholarships(limit?: number): Promise<Scholarship[]>
  scholarshipPage(args?: EntityPageArgs): Promise<PagePayload<Scholarship>>
  scholarshipDetail(scholarshipId: string): Promise<ScholarshipDetailPayload>
  qiltPage(args?: Record<string, unknown>): Promise<unknown>
  filterOptionPage(args?: Record<string, unknown>): Promise<unknown>
  qiltFilterOptions(survey?: string): Promise<unknown>
  prismsPage(args?: Record<string, unknown>): Promise<unknown>
  prismsFilterOptions(): Promise<unknown>
  rankingSummary(): Promise<unknown>
  rankingFilters(systemCode?: string): Promise<unknown>
  rankingObservations(args?: Record<string, unknown>): Promise<unknown>
  rankingImports(args?: Record<string, unknown>): Promise<unknown>
  uploadRankingPublisherFile(args: Record<string, unknown>): Promise<unknown>
  importRankingPublisherUrl(args: Record<string, unknown>): Promise<unknown>
  rankingPublisherControl(args: Record<string, unknown>): Promise<unknown>
  providerAssetSummary(args?: Record<string, unknown>): Promise<unknown>
  providerAssetCoverage(args?: Record<string, unknown>): Promise<unknown>
  providerAssetAccess(providerId: string): Promise<unknown>
  providerContactsPage(args?: Record<string, unknown>): Promise<unknown>
  providerContactDetail(id: string): Promise<unknown>
  providerContactImports(args?: Record<string, unknown>): Promise<unknown>
  providerContactImportDetail(id: string): Promise<unknown>
  providerContactManage(action: string, payload?: Record<string, unknown>): Promise<unknown>
  uploadProviderContactFile(args: Record<string, unknown>): Promise<unknown>
  providerContactImportControl(args: Record<string, unknown>): Promise<unknown>
  providerContactExportAudit(args?: Record<string, unknown>): Promise<unknown>
  evidencePage(args?: Record<string, unknown>): Promise<unknown>
  evidenceFilterOptions(): Promise<unknown>
  evidenceDetail(evidenceId: string): Promise<unknown>
  evidenceObservations(evidenceId: string, args?: Record<string, unknown>): Promise<unknown>
  evidenceEntities(evidenceId: string, args?: Record<string, unknown>): Promise<unknown>
  evidenceAccess(evidenceId: string, mode?: 'preview' | 'download'): Promise<unknown>
  reviewsPage(args?: Record<string, unknown>): Promise<unknown>
  reviewFilterOptions(): Promise<{ domains: string[]; statuses: string[] }>
  categories(): Promise<unknown[]>
  attributes(): Promise<Attribute[]>
  attributeFamilies(): Promise<AttributeFamily[]>
  attributeGroups(): Promise<AttributeGroup[]>
  attributeOptions(limit?: number): Promise<AttributeOption[]>
  completenessProfiles(): Promise<CompletenessProfile[]>
  completenessCourses(limit?: number): Promise<Course[]>
  evidence(limit?: number): Promise<Evidence[]>
  jobs(limit?: number): Promise<unknown>
  reviews(limit?: number): Promise<unknown>
  regulatorySources(): Promise<unknown>
  layer1Job(jobId: string): Promise<unknown>
  latestLayer1Job(country?: string): Promise<unknown>
  runLayer1(args?: Record<string, unknown>): Promise<unknown>
  runLayer2AStatsCan(args?: Record<string, unknown>): Promise<unknown>
  resetDatabase(): Promise<unknown>
  searchCourses(query: string, limit?: number): Promise<Course[]>
}

export interface SupabaseModuleContract {
  supabase: SupabaseClient
  api: CourseFinderApi
  adminRead<T extends AdminReadOperation>(operation: T, args?: Record<string, unknown>): Promise<AdminReadPayload<T>>
}
