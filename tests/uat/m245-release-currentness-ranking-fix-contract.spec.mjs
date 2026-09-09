import {test,expect} from '@playwright/test'
import fs from 'node:fs'

test('v2.15.75 release pill exposes QS ranking corrective fixes',()=>{
  const current=fs.readFileSync('src/release-currentness-entry.js','utf8')
  expect(current).toContain("const VERSION='2.15.75'")
  expect(current).toContain('QS ranking duplicate cleanup and 2026/2027 acquisition correction')
  expect(current).toContain('Bug / UI fixes')
  expect(current).toContain('Fixed duplicate QS edition rows in Sources & Imports')
  expect(current).toContain('Fixed duplicate active QS 2024/2025 lifecycle state')
  expect(current).toContain('Fixed the QS 2026/2027 official-static completeness contract')
  expect(current).toContain('pending security task #60')
})
