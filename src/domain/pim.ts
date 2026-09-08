import type { Attribute, PimAttributeValue } from '../types/pim'

const VALUE_KEYS: Array<keyof PimAttributeValue> = [
  'value_text',
  'value_number',
  'value_boolean',
  'value_date',
  'value_datetime',
  'value_code',
  'value_json',
]

export const CORE_COURSE_ATTRIBUTE_CODES = new Set([
  'course_description',
  'provider_name',
  'course_code',
  'study_level',
  'field_of_study',
  'duration',
  'delivery_mode',
  'lifecycle_status',
  'publication_status',
  'official_course_url',
])

export function pimValue(value: PimAttributeValue): unknown {
  for (const key of VALUE_KEYS) {
    const candidate = value[key]
    if (candidate !== null && candidate !== undefined && candidate !== '') return candidate
  }
  return null
}

export function pimDisplayValue(attribute: Attribute, value: PimAttributeValue, optionLabels: Map<string, string>): unknown {
  const raw = pimValue(value)
  if (raw === null) return null
  if (attribute.data_type !== 'select' && attribute.data_type !== 'multiselect') return raw

  const labelFor = (code: unknown) => {
    if (typeof code !== 'string' && typeof code !== 'number') return code
    const normalized = String(code)
    return optionLabels.get(`${attribute.id}:${normalized}`) ?? normalized
  }

  if (value.value_code !== null && value.value_code !== undefined && value.value_code !== '') {
    return labelFor(value.value_code)
  }
  if (value.value_json !== null && value.value_json !== undefined) {
    return Array.isArray(raw) ? raw.map(labelFor) : labelFor(raw)
  }
  return raw
}

export function pimOptionLabelsForValue(value: PimAttributeValue, fallback: Map<string, string>): Map<string, string> {
  const map = new Map(fallback)
  for (const [code, label] of Object.entries(value.option_labels || {})) {
    map.set(`${value.attribute_id}:${code}`, String(label))
  }
  return map
}

export function activeAttributes(attributes: Attribute[], entityType: string): Attribute[] {
  return attributes
    .filter(attribute => attribute.entity_type === entityType)
    .filter(attribute => !attribute.status || attribute.status === 'active')
    .sort((a, b) => (a.display_order ?? 0) - (b.display_order ?? 0) || a.name.localeCompare(b.name))
}

export function dynamicCourseAttributes(attributes: Attribute[]): Attribute[] {
  return activeAttributes(attributes, 'course').filter(attribute => !CORE_COURSE_ATTRIBUTE_CODES.has(attribute.code))
}

export function pimScopeKey(value: PimAttributeValue): string {
  return `${value.locale ?? ''}\u0000${value.channel_code ?? ''}`
}

export function pimScopeLabel(value: PimAttributeValue): string {
  const parts = [value.locale, value.channel_code].filter(Boolean)
  return parts.length ? parts.join(' · ') : ''
}

export function valuesByAttribute(values: PimAttributeValue[]): Map<string, PimAttributeValue[]> {
  const map = new Map<string, PimAttributeValue[]>()
  for (const value of values) {
    const key = value.attribute_code || value.attribute_id
    const existing = map.get(key) || []
    existing.push(value)
    existing.sort((a, b) => (a.position ?? 0) - (b.position ?? 0))
    map.set(key, existing)
  }
  return map
}

export function valuesByScope(values: PimAttributeValue[]): Map<string, PimAttributeValue[]> {
  const map = new Map<string, PimAttributeValue[]>()
  for (const value of values) {
    const key = pimScopeKey(value)
    const existing = map.get(key) || []
    existing.push(value)
    existing.sort((a, b) => (a.position ?? 0) - (b.position ?? 0))
    map.set(key, existing)
  }
  return map
}

export function hasRenderablePimValues(values: PimAttributeValue[] | null | undefined): boolean {
  return Boolean(values?.some(value => pimValue(value) !== null))
}
