import { describe, expect, it } from 'vitest'
import { dynamicCourseAttributes, hasRenderablePimValues, pimValue, valuesByAttribute } from './pim'

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

  it('groups multi-value rows by attribute and preserves position', () => {
    const map = valuesByAttribute([
      { attribute_id: 'a3', attribute_code: 'course_keywords', value_text: 'second', position: 2 },
      { attribute_id: 'a3', attribute_code: 'course_keywords', value_text: 'first', position: 1 },
    ])
    expect(map.get('course_keywords')?.map(x => x.value_text)).toEqual(['first', 'second'])
  })

  it('detects whether a payload contains anything renderable', () => {
    expect(hasRenderablePimValues([])).toBe(false)
    expect(hasRenderablePimValues([{ attribute_id: 'a2', value_text: null }])).toBe(false)
    expect(hasRenderablePimValues([{ attribute_id: 'a2', value_boolean: false }])).toBe(true)
  })
})
