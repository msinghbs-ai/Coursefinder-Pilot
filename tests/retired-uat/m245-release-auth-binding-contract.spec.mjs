import {test,expect} from '@playwright/test'
import fs from 'node:fs'
test('release pill remains bindable after delayed authentication',()=>{
  const release=fs.readFileSync('src/pim-version-entry.js','utf8')
  expect(release).toContain('function bindReleasePill(el)')
  expect(release).toContain('function watchReleasePills()')
  expect(release).toContain("observer.observe(document.documentElement,{childList:true,subtree:true})")
  expect(release).toContain("if(el.dataset.releaseNotesBound==='true')return")
  expect(release).toContain("el.addEventListener('click',openReleaseNotes)")
  expect(release).toContain("event.key==='Enter'||event.key===' '")
})
