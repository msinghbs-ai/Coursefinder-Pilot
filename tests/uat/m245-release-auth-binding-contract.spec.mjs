// Guards: M2.4.5: release pill opens the notes by click, Enter or Space and returns focus on close
import {test,expect} from '@playwright/test'
import fs from 'node:fs'
// v2.15.291: the pill is part of the signed-in shell React draws, so it works however late sign-in finishes; nothing binds it
// after drawing any more (pim-version-entry.js and its MutationObserver are retired).
test('release pill opens the notes by click, Enter or Space and returns focus on close',()=>{
  const release=fs.readFileSync('src/ReleaseNotes.jsx','utf8')
  expect(release).toContain('export function ReleasePill()')
  expect(release).toContain("onClick={()=>setOpen(true)}")
  expect(release).toContain("e.key==='Enter'||e.key===' '")
  expect(release).toContain("if(e.key==='Escape')onClose()")
  expect(release).toContain('pillRef.current?.focus()')
  expect(release).toContain('aria-labelledby="pim-release-notes-title"')
  expect(release).toContain('>Release notes</h2>')
  expect(fs.readFileSync('src/mature-main.jsx','utf8')).toContain('<ReleasePill/>')
})
