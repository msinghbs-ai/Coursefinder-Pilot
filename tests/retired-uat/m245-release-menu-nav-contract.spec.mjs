import {test,expect} from '@playwright/test'
import fs from 'node:fs'
test('breadcrumb navigation and release pill use maintained dialog authority',()=>{
  const ui=fs.readFileSync('src/mature-main.jsx','utf8')
  const release=fs.readFileSync('src/pim-version-entry.js','utf8')
  expect(ui).toContain('setPage(label);setRouteParams(new URLSearchParams(q));if(location.hash!==next)location.hash=next')
  expect(ui).toContain('<span className="m-release-pill"><span className="m-live-dot"/><span className="m-release-version-label">v{UI_VERSION}</span></span>')
  expect(ui).not.toContain('<details className="m-release-menu">')
  expect(release).toContain("querySelectorAll('.m-release-pill')")
  expect(release).toContain('m-release-notes-list')
  expect(release).toContain('Bug / UI fixes')
  expect(release).toContain('release.bugFixes')
  expect(release).toContain('new MutationObserver')
  expect(release).toContain("node.querySelectorAll?.('.m-release-pill').forEach(bindReleasePill)")
  expect(release).not.toContain('attempts<20')
  expect(release).not.toContain('setTimeout(sync,150)')
})
