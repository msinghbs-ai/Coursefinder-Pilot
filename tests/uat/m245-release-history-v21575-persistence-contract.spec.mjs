import {test,expect} from '@playwright/test'
import fs from 'node:fs'

test('v2.15.77 is canonical while v2.15.76 and v2.15.75 remain retained in release history',()=>{
  const history=fs.readFileSync('src/pim-version-entry.js','utf8')
  const shell=fs.readFileSync('src/mature-main.jsx','utf8')
  const current=fs.readFileSync('src/release-currentness-entry.js','utf8')
  const html=fs.readFileSync('index.html','utf8')

  expect(history).toContain("const VERSION='2.15.77'")
  expect(history).toContain("{version:'2.15.76'")
  expect(history).toContain("{version:'2.15.75'")
  expect(history).toContain("title:'QS ranking duplicate cleanup and 2026/2027 acquisition correction'")
  expect(history).toContain("bugFixes:['Fixed duplicate QS edition rows in Sources & Imports")
  expect(history.indexOf("{version:'2.15.75'")).toBeLessThan(history.indexOf("{version:'2.15.74'"))
  expect(history).toContain("{version:'2.15.77'")
  expect(history.indexOf("{version:'2.15.77'")).toBeLessThan(history.indexOf("{version:'2.15.76'"))
  expect(history.indexOf("{version:'2.15.76'")).toBeLessThan(history.indexOf("{version:'2.15.75'"))
  expect(shell).toContain("const UI_VERSION='2.15.77'")
  expect(current).toContain("const VERSION='2.15.77'")
  expect(html).toContain('<title>Coursefinder PIM Admin v2.15.77</title>')
})
