import {test,expect} from '@playwright/test'
import fs from 'node:fs'
test('breadcrumb navigation and release pill have one native authority',()=>{
  const ui=fs.readFileSync('src/mature-main.jsx','utf8')
  const legacy=fs.readFileSync('src/pim-version-entry.js','utf8')
  expect(ui).toContain('setPage(label);setRouteParams(new URLSearchParams(q));if(location.hash!==next)location.hash=next')
  expect(ui).toContain('Bug / UI fixes')
  expect(ui).toContain('Release notes')
  expect(ui).toContain('RELEASE_NOTES.map')
  expect(ui).toContain('UI_FIXES.map')
  expect(legacy).not.toContain("querySelector('.m-release-pill')")
  expect(legacy).not.toContain("querySelectorAll('.m-release-pill')")
})
