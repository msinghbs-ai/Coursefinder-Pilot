import {test,expect} from '@playwright/test'
import fs from 'node:fs'

test('v2.15.82 is the release candidate while v2.15.79 remains the accepted recovery release and v2.15.78 retained history',()=>{
  const manifest=fs.readFileSync('src/release-manifest.js','utf8')
  const history=fs.readFileSync('src/pim-version-entry.js','utf8')
  const shell=fs.readFileSync('src/mature-main.jsx','utf8')
  const current=fs.readFileSync('src/release-currentness-entry.js','utf8')
  const html=fs.readFileSync('index.html','utf8')
  const pkg=JSON.parse(fs.readFileSync('package.json','utf8'))
  const changelog=fs.readFileSync('CHANGELOG.md','utf8')

  expect(manifest).toContain("export const UI_VERSION='2.15.82'")
  expect(manifest).toContain("export const PACKAGE_VERSION='0.1.9'")
  expect(manifest).toContain("export const RELEASE_STATE='candidate'")
  expect(manifest).toContain('export const ACCEPTED_RELEASES=[')
  expect(manifest).toContain("version:'2.15.79'")
  expect(manifest).toContain("packageVersion:'0.1.6'")
  expect(manifest).toContain("pilotMain:'32be4e96a8df342deba3011f9740dc1230a672b2'")
  expect(manifest).toContain('export const RECOVERY_RELEASE=ACCEPTED_RELEASES[0]')
  expect(manifest).not.toContain('PREVIOUS_ACCEPTED_RELEASE')

  expect(pkg.version).toBe('0.1.9')
  expect(changelog).toContain('## 0.1.9 — 23 Sep 2026')
  expect(changelog).toContain('**v2.15.82**')
  expect(changelog).toContain('## 0.1.8 — 23 Sep 2026')
  expect(changelog).toContain('**v2.15.81**')
  expect(changelog).toContain('## 0.1.7 — 23 Sep 2026')
  expect(changelog).toContain('**v2.15.80**')
  expect(changelog).toContain('## 0.1.6 — 14 Sep 2026')
  expect(changelog).toContain('**v2.15.79**')
  expect(changelog).toContain('## 0.1.5 — 11 Sep 2026')
  expect(changelog).toContain('**v2.15.78**')

  // Legacy history remains retained display content only; it no longer decides recovery authority.
  expect(history).toContain("const VERSION='2.15.78'")
  expect(history).toContain("{version:'2.15.78'")
  expect(history).toContain("{version:'2.15.77'")
  expect(history).toContain("{version:'2.15.76'")
  expect(history).toContain("{version:'2.15.75'")
  expect(history.indexOf("{version:'2.15.78'")).toBeLessThan(history.indexOf("{version:'2.15.77'"))

  // Static shell fallback must remain an immutable retained release; runtime currentness comes only from the manifest overlay.
  expect(shell).toContain("const UI_VERSION='2.15.78'")
  expect(current).toContain("import{UI_VERSION as VERSION,RELEASE}from'./release-manifest.js'")
  expect(current).not.toMatch(/const VERSION='2\.15\.\d+'/)
  expect(current).toContain('document.title=`Coursefinder PIM Admin v${VERSION}`')
  expect(html).toContain('<title>Coursefinder PIM Admin</title>')
  expect(html).not.toMatch(/Coursefinder PIM Admin v2\.15\.\d+/)
})
