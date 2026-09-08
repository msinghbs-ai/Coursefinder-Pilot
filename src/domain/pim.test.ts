import { describe, expect, it } from 'vitest'
import { dynamicCourseAttributes, hasRenderablePimValues, pimDisplayValue, pimOptionLabelsForValue, pimScopeKey, pimScopeLabel, pimValue, valuesByAttribute, valuesByScope } from './pim'

const attributes = [
  { id: 'a1', code: 'course_description', name: 'Description', entity_type: 'course', data_type: 'richtext', display_order: 40, status: 'active' },
  { id: 'a2', code: 'course_prerequisites', name: 'Prerequisites', entity_type: 'course', data_type: 'richtext', display_order: 10, status: 'active' },
  { id: 'a3', code: 'course_keywords', name: 'Keywords', entity_type: 'course', data_type: 'multiselect', display_order: 20, status: 'active' },
]

it('keeps hardcoded course description out of dynamic PIM fields', () => {
  expect(dynamicCourseAttributes(attributes).map(x => x.code)).toEqual(['course_prerequisites', 'course_keywords'])
})

describe('PIM value normalization', () => {
  it('returns the first populated typed value', () => {
    expect(pimValue({ attribute_id: 'a2', value_text: 'Maths required' })).toBe('Maths required')
    expect(pimValue({ attribute_id: 'a3', value_json: ['engineering'] })).toEqual(['engineering'])
  })

  it('maps select and multiselect JSON codes to configured labels', () => {
    const optionLabels = new Map([['a3:engineering', 'Engineering'], ['a3:technology', 'Technology']])
    expect(pimDisplayValue(attributes[2], { attribute_id: 'a3', value_json: ['engineering', 'technology'] }, optionLabels)).toEqual(['Engineering', 'Technology'])
    expect(pimDisplayValue(attributes[2], { attribute_id: 'a3', value_code: 'engineering' }, optionLabels)).toBe('Engineering')
  })

  it('keeps embedded option labels scoped to each value', () => {
    const fallback = new Map([['a3:engineering', 'Engineering']])
    const au = { attribute_id: 'a3', locale: 'en-AU', channel_code: 'website', value_code: 'engineering', option_labels: { engineering: 'Engineering' } }
    const fr = { attribute_id: 'a3', locale: 'fr-FR', channel_code: 'website', value_code: 'engineering', option_labels: { engineering: 'Ingénierie' } }
    expect(pimDisplayValue(attributes[2], au, pimOptionLabelsForValue(au, fallback))).toBe('Engineering')
    expect(pimDisplayValue(attributes[2], fr, pimOptionLabelsForValue(fr, fallback))).toBe('Ingénierie')
    expect(fallback.get('a3:engineering')).toBe('Engineering')
  })

  it('groups multi-value rows by attribute and preserves position', () => {
    const map = valuesByAttribute([
      { attribute_id: 'a3', attribute_code: 'course_keywords', value_text: 'second', position: 2 },
      { attribute_id: 'a3', attribute_code: 'course_keywords', value_text: 'first', position: 1 },
    ])
    expect(map.get('course_keywords')?.map(x => x.value_text)).toEqual(['first', 'second'])
  })

  it('preserves locale and channel partitions independently', () => {
    const values = [
      { attribute_id: 'a2', value_text: 'global' },
      { attribute_id: 'a2', value_text: 'au-web', locale: 'en-AU', channel_code: 'website' },
      { attribute_id: 'a2', value_text: 'au-app', locale: 'en-AU', channel_code: 'app' },
      { attribute_id: 'a2', value_text: 'nz-web', locale: 'en-NZ', channel_code: 'website' },
    ]
    const partitions = valuesByScope(values)
    expect(partitions.size).toBe(4)
    expect(partitions.get(pimScopeKey(values[0]))?.map(x => x.value_text)).toEqual(['global'])
    expect(partitions.get(pimScopeKey(values[1]))?.map(x => x.value_text)).toEqual(['au-web'])
    expect(pimScopeLabel(values[0])).toBe('')
    expect(pimScopeLabel(values[1])).toBe('en-AU · website')
  })

  it('keeps positions ordered within each locale/channel partition', () => {
    const partitions = valuesByScope([
      { attribute_id: 'a3', value_text: 'second', locale: 'en-AU', channel_code: 'website', position: 2 },
      { attribute_id: 'a3', value_text: 'first', locale: 'en-AU', channel_code: 'website', position: 1 },
      { attribute_id: 'a3', value_text: 'other', locale: 'en-NZ', channel_code: 'website', position: 1 },
    ])
    expect(partitions.get('en-AU\u0000website')?.map(x => x.value_text)).toEqual(['first', 'second'])
    expect(partitions.get('en-NZ\u0000website')?.map(x => x.value_text)).toEqual(['other'])
  })

  it('detects whether a payload contains anything renderable', () => {
    expect(hasRenderablePimValues([])).toBe(false)
    expect(hasRenderablePimValues([{ attribute_id: 'a2', value_text: null }])).toBe(false)
    expect(hasRenderablePimValues([{ attribute_id: 'a2', value_boolean: false }])).toBe(true)
  })
})
