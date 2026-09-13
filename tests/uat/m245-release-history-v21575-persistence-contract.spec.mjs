import {test,expect} from '@playwright/test'
import fs from 'node:fs'

test('v2.15.79 candidate uses one manifest while v2.15.78 remains the accepted recovery baseline and retained history',()=>{
  const manifest=fs.readFileSync('src/release-manifest.js','utf8')
  const history=fs.readFileSync('src/pim-version-entry.js','utf8')
  const shell=fs.readFileSync('src/mature-main.jsx','utf8')
  const current=fs.readFileSync('src/release-currentness-entry.js','utf8')
  const html=fs.readFileSync('index.html','utf8')
  const pkg=JSON.parse(fs.readFileSync('package.json','utf8'))
  const changelog=fs.readFileSync('CHANGELOG.md','utf8')

  expect(manifest).toContain("export const UI_VERSION='2.15.79'")
  expect(manifest).toContain("export const PACKAGE_VERSION='0.1.6'")
  expect(manifest).toContain("version:'2.15.78'")
  expect(manifest).toContain("packageVersion:'0.1.5'")
  expect(manifest).toContain("pilotMain:'7cf5cc72296ca82e6e026606a61f449ede4ead45'")

  expect(pkg.version).toBe('0.1.6')
  expect(changelog).toContain('## 0.1.6 — 14 Sep 2026')
  expect(changelog).toContain('**v2.15.79**')
  expect(changelog).toContain('## 0.1.5 — 11 Sep 2026')
  expect(changelog).toContain('**v2.15.78**')

  expect(history).toContain("const VERSION='2.15.78'")
  expect(history).toContain("{version:'2.15.78'")
  expect(history).toContain("{version:'2.15.77'")
  expect(history).toContain("{version:'2.15.76'")
  expect(history).toContain("{version:'2.15.75'")
  expect(history.indexOf("{version:'2.15.78'")).toBeLessThan(history.indexOf("{version:'2.15.77'"))
  expect(history.indexOf("{version:'2.15.77'")).toBeLessThan(history.indexOf("{version:'2.15.76'"))
  expect(history.indexOf("{version:'2.15.76'")).toBeLessThan(history.indexOf("{version:'2.15.75'"))

  // Bootstrap/history remain the last accepted release until the candidate passes merge + deployed acceptance.
  expect(shell).toContain("const UI_VERSION='2.15.78'")
  expect(current).toContain("import{UI_VERSION as VERSION,RELEASE}from'./release-manifest.js'")
  expect(current).not.toMatch(/const VERSION='2\.15\.\d+'/)
  expect(current).toContain('document.title=`Coursefinder PIM Admin v${VERSION}`')
  expect(html).toContain('<title>Coursefinder PIM Admin</title>')
  expect(html).not.toMatch(/Coursefinder PIM Admin v2\.15\.\d+/)
})
