export interface BaseEntity {
  id: string
  stable_key?: string | null
  lifecycle_status?: string | null
  publication_status?: string | null
  created_at?: string | null
  updated_at?: string | null
  [key: string]: unknown
}

export interface Provider extends BaseEntity {
  canonical_name?: string | null
  display_name?: string | null
  country_code?: string | null
  website?: string | null
}

export interface Course extends BaseEntity {
  canonical_title?: string | null
  display_title?: string | null
  course_code?: string | null
  provider_id?: string | null
  provider_name?: string | null
  level_code?: string | null
  level_name?: string | null
  field_code?: string | null
  field_name?: string | null
  description?: string | null
  course_url?: string | null
  duration_value?: number | null
  duration_unit?: string | null
  delivery_mode?: string | null
}

export interface Campus extends BaseEntity {
  name?: string | null
  campus_code?: string | null
  provider_id?: string | null
  provider_name?: string | null
  country_code?: string | null
  subdivision_code?: string | null
  subdivision_name?: string | null
  city?: string | null
  postcode?: string | null
}

export interface Scholarship extends BaseEntity {
  name?: string | null
  provider_id?: string | null
  provider_name?: string | null
  country_code?: string | null
  status?: string | null
}

export interface Evidence extends BaseEntity {
  evidence_type?: string | null
  source_url?: string | null
  storage_path?: string | null
  content_hash?: string | null
  captured_at?: string | null
  valid_from?: string | null
  valid_to?: string | null
}
