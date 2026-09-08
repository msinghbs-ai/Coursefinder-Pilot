import {test,expect} from '@playwright/test'
import fs from 'node:fs'
test('version pill preserves maintained accessible release history and bug fixes',()=>{
  const ui=fs.readFileSync('src/mature-main.jsx','utf8')
  const release=fs.readFileSync('src/pim-version-entry.js','utf8')
  expect(ui).toContain('<span className="m-release-pill"><span className="m-live-dot"/><span className="m-release-version-label">v{UI_VERSION}</span></span>')
  expect(ui).not.toContain('<details className="m-release-menu">')
  expect(release).toContain("querySelectorAll('.m-release-pill')")
  expect(release).toContain('m-release-notes-list')
  expect(release).toContain('role="dialog" aria-modal="true"')
  expect(release).toContain("event.key==='Escape'")
  expect(release).toContain("document.querySelector('.m-release-pill[role=\"button\"]')?.focus()")
  expect(release).toContain('Bug / UI fixes')
  expect(release).toContain('release.bugFixes')
  expect(release).not.toContain('.m-release-pill-legacy')
})
