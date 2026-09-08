export type PimEntityType = 'provider' | 'course' | 'scholarship' | string

export interface AttributeFamily {
  id: string
  code: string
  name: string
  entity_type: PimEntityType
  description?: string | null
  is_default?: boolean
  status?: string
  created_at?: string
  updated_at?: string
}

export interface AttributeGroup {
  id: string
  code: string
  name: string
  entity_type: PimEntityType
  description?: string | null
  display_order?: number
  status?: string
}

export interface Attribute {
  id: string
  code: string
  name: string
  entity_type: PimEntityType
  group_id?: string | null
  data_type: string
  unit_code?: string | null
  validation_rules?: Record<string, unknown>
  is_required_default?: boolean
  is_unique?: boolean
  is_filterable?: boolean
  is_searchable?: boolean
  include_in_vector?: boolean
  vector_weight?: number
  is_localisable?: boolean
  is_channel_scoped?: boolean
  is_multivalue?: boolean
  is_bulk_editable?: boolean
  display_order?: number
  status?: string
}

export interface AttributeOption {
  id: string
  attribute_id: string
  code: string
  label: string
  locale?: string | null
  metadata?: Record<string, unknown>
  display_order?: number
  status?: string
}

export interface CompletenessProfile {
  id: string
  code: string
  name: string
  entity_type: PimEntityType
  family_id?: string | null
  country_id?: string | null
  channel_code?: string | null
  minimum_publish_score?: number | null
  status?: string
}

export interface PimAttributeValue {
  id?: string
  entity_id?: string
  attribute_id: string
  attribute_code?: string
  attribute_name?: string
  attribute_data_type?: string
  attribute_display_order?: number | null
  attribute_is_multivalue?: boolean
  option_labels?: Record<string, string>
  value_text?: string | null
  value_number?: number | null
  value_boolean?: boolean | null
  value_date?: string | null
  value_datetime?: string | null
  value_code?: string | null
  value_json?: unknown
  locale?: string | null
  channel_code?: string | null
  position?: number
  source_id?: string | null
  evidence_id?: string | null
  confidence?: number | null
  review_status?: string | null
  is_preferred?: boolean
  valid_from?: string | null
  valid_to?: string | null
}

export interface PimGovernanceBundle {
  families: AttributeFamily[]
  groups: AttributeGroup[]
  attributes: Attribute[]
  options: AttributeOption[]
  completeness_profiles: CompletenessProfile[]
  family_groups?: Array<Record<string, unknown>>
  family_attributes?: Array<Record<string, unknown>>
  counts?: Record<string, number>
  limit?: number
}
