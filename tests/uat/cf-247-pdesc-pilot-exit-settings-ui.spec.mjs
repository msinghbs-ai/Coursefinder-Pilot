// Guards: Platform Admin 9 Nov 2026 all-provider description pilot exit; F-PDESC.04 and G2.
// A documented empty provider whitelist is valid; other lists are still non-empty.
// The rank-6 audited admin_toolsets_write RPC, not SQL impersonation, remains the only save path.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { parseSettingList, validSettingList, settingListReadout } from '../../src/settings-list-validation.js'

const screen = fs.readFileSync('src/SettingsRegister.jsx', 'utf8')

test('an empty provider whitelist means all providers within country/type scope', () => {
  expect(parseSettingList('')).toEqual([])
  expect(parseSettingList('  , , ')).toEqual([])
  expect(validSettingList('pdesc.provider_keys', [])).toBe(true)
  expect(settingListReadout('pdesc.provider_keys', [])).toContain('All eligible providers')
  expect(settingListReadout('pdesc.provider_keys', [])).toContain('country and type')
})

test('every other operational list still requires at least one entry', () => {
  for (const key of ['pdesc.countries', 'pdesc.provider_types', 'pdesc.refused_path_words', 'run_now.jobs', 'zoho.countries']) {
    expect(validSettingList(key, [])).toBe(false)
    expect(validSettingList(key, parseSettingList('AU, NZ'))).toBe(true)
  }
  expect(validSettingList('pdesc.provider_keys', ['provider:cricos:00008c'])).toBe(true)
  expect(validSettingList('pdesc.provider_keys', null)).toBe(false)
})

test('screen routes empty array through existing rank-6 audited Admin settings action', () => {
  expect(screen).toContain('validSettingList(s.key,list)')
  expect(screen).toContain('parseSettingList(v)')
  expect(screen).toContain('settingListReadout(s.key,s.value)')
  expect(screen).toContain("s.key==='pdesc.provider_keys'")
  expect(screen).toContain('Clear this list for all eligible providers')
  expect(screen).toContain("supabase.rpc('admin_toolsets_write'")
  expect(screen).toContain("p_action:'setting'")
  expect(screen).toContain("toolset:'pipeline',key,value,reason")
  expect(screen).not.toContain("ls?list.length>0")
})
