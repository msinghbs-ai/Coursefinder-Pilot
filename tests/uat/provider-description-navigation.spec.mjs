// Guards: Provider Description autonomy mandate §6: direct existing Layer 4 navigation preserves exact review identity and production keyset order.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'
import { layer4DeepLinkCursor } from '../../src/layer4-deep-link.js'

const contract = JSON.parse(fs.readFileSync('tests/fixtures/provider-description-autonomy/navigation-contract.json', 'utf8'))

test('exact decision cursor uses captured production kind order, preserves microseconds and precedes the target UUID', () => {
  expect(crypto.createHash('md5').update(contract.items_definition).digest('hex')).toBe(contract.items_md5)
  expect(contract.items_definition).toContain('(x.o, x.kind, x.created_at, x.ref) > (v_ao, v_ak, v_aat, v_ar) order by o, kind, created_at, ref')
  const stamp = '2026-11-04T12:34:56.123456+00:00'
  expect(layer4DeepLinkCursor(contract.kinds, 'provider_description', 'ffffffff-ffff-ffff-ffff-ffffff000000', stamp)).toEqual({
    after_o: contract.kinds.provider_description.order, after_kind: 'provider_description', after_at: stamp, after_ref: 'ffffffff-ffff-ffff-ffff-fffffeffffff',
  })
  // Kind order comes from metadata rather than from the description kind's present ordinal.
  expect(layer4DeepLinkCursor({ provider_description: { order: 37 } }, 'provider_description', '00000000-0000-0000-0000-000000000001', stamp).after_o).toBe(37)
})

test('the minimum UUID remains reachable and malformed routes do not invent a keyset cursor', () => {
  const stamp = '2026-11-04T12:34:56.123456+00:00'
  expect(layer4DeepLinkCursor(contract.kinds, 'provider_description', '00000000-0000-0000-0000-000000000000', stamp).after_ref).toBe('')
  for (const [kinds, ref, at] of [
    [{}, '00000000-0000-0000-0000-000000000001', stamp],
    [{ provider_description: { order: null } }, '00000000-0000-0000-0000-000000000001', stamp],
    [{ provider_description: { order: 1.5 } }, '00000000-0000-0000-0000-000000000001', stamp],
    [contract.kinds, 'an unrelated reference', stamp],
    [contract.kinds, '00000000-0000-0000-0000-000000000001', 'invalid timestamp'],
  ]) expect(layer4DeepLinkCursor(kinds, 'provider_description', ref, at)).toBeNull()
})
