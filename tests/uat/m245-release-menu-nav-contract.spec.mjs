// Guards: M2.4.5: breadcrumb navigation and release pill use maintained dialog authority
import {test,expect} from '@playwright/test'
import fs from 'node:fs'
test('breadcrumb navigation and release pill use maintained dialog authority',()=>{
  const ui=fs.readFileSync('src/mature-main.jsx','utf8')
  // v2.15.291: the pill and its release notes are drawn by React (ReleaseNotes.jsx); the post-render pim-version-entry.js is retired.
  const release=fs.readFileSync('src/ReleaseNotes.jsx','utf8')
  // v2.15.107: navigation resolves through nav-map (old names and addresses redirect) and writes one canonical address.
  expect(ui).toContain('setRoute(r);if(location.hash!==next)location.hash=next')
  expect(ui).toContain("import{ReleasePill,applyReleaseIdentity}from'./ReleaseNotes'")
  expect(ui).toContain('<ReleasePill/>')
  expect(ui).not.toContain('<details className="m-release-menu">')
  expect(release).toContain('<span ref={pillRef} className="m-release-pill" role="button" tabIndex={0} aria-haspopup="dialog"')
  expect(release).toContain('<span className="m-live-dot"/><span className="m-release-version-label">v{UI_VERSION}</span>')
  expect(release).toContain('m-release-notes-list')
  expect(release).toContain('Bug / UI fixes')
  expect(release).toContain('release.bugFixes')
  expect(release).not.toContain('MutationObserver')
  expect(release).not.toContain('querySelector')
  expect(fs.existsSync('src/pim-version-entry.js')).toBe(false)
})
