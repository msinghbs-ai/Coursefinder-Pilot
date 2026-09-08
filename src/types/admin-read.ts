import type { Campus, Course, Evidence, Provider, Scholarship } from './entities'
import type { PimAttributeValue, PimGovernanceBundle } from './pim'

export interface PagePayload<T> {
  items?: T[]
  rows?: T[]
  total?: number
  limit?: number
  offset?: number
  [key: string]: unknown
}

export interface ProviderDetailPayload extends Provider {
  courses?: Course[] | PagePayload<Course>
  evidence?: Evidence[] | PagePayload<Evidence>
  contextual_insights?: unknown
  ranking_context?: unknown
  provider_asset_context?: unknown
  scholarship_context?: unknown
  pim_attribute_values?: PimAttributeValue[]
}

export interface CourseDetailPayload extends Course {
  campuses?: Campus[]
  related_campuses?: Campus[]
  evidence?: Evidence[]
  fee_summary?: Record<string, unknown>
  entry_summary?: Record<string, unknown>
  taxonomy_summary?: Record<string, unknown>
  state_summary?: Record<string, unknown>
  contextual_insights?: unknown
  ranking_context?: unknown
  field_states?: Array<Record<string, unknown>>
  pim_attribute_values?: PimAttributeValue[]
}

export interface ScholarshipDetailPayload extends Scholarship {
  semantic_summary?: unknown
  pim_attribute_values?: PimAttributeValue[]
}

export interface AdminReadPayloadMap {
  providers_page: PagePayload<Provider>
  provider_detail: ProviderDetailPayload
  courses_page: PagePayload<Course>
  course_detail: CourseDetailPayload
  scholarships_page: PagePayload<Scholarship>
  scholarship_detail: ScholarshipDetailPayload
  campuses_page: PagePayload<Campus>
  attributes: PimGovernanceBundle
  [operation: string]: unknown
}

export type AdminReadOperation = keyof AdminReadPayloadMap
export type AdminReadPayload<T extends AdminReadOperation> = AdminReadPayloadMap[T]
