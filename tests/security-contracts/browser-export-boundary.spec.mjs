import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'

const read = filePath => fs.readFile(filePath, 'utf8')

function stripComments(source) {
  let out = ''
  let i = 0
  let quote = null
  while (i < source.length) {
    const ch = source[i]
    const next = source[i + 1]
    if (quote) {
      out += ch
      if (ch === '\\' && i + 1 < source.length) { out += next; i += 2; continue }
      if (ch === quote) quote = null
      i += 1
      continue
    }
    if (ch === "'" || ch === '"' || ch === '`') { quote = ch; out += ch; i += 1; continue }
    if (ch === '/' && next === '/') {
      const end = source.indexOf('\n', i + 2)
      const stop = end < 0 ? source.length : end
      out += ' '.repeat(stop - i)
      i = stop
      continue
    }
    if (ch === '/' && next === '*') {
      const end = source.indexOf('*/', i + 2)
      const stop = end < 0 ? source.length : end + 2
      out += ' '.repeat(stop - i)
      i = stop
      continue
    }
    out += ch
    i += 1
  }
  return out
}

async function walk(dir) {
  const entries = await fs.readdir(dir, { withFileTypes: true })
  const files = []
  for (const entry of entries) {
    const filePath = `${dir}/${entry.name}`
    if (entry.isDirectory()) files.push(...await walk(filePath))
    else if (/\.[cm]?[jt]sx?$/i.test(entry.name)) files.push(filePath)
  }
  return files
}

test('Supabase SDK wildcard re-exports are forbidden outside the central client', async () => {
  for (const file of await walk('src')) {
    if (file === 'src/lib/supabase.ts') continue
    const executable = stripComments(await read(file))
    expect(executable, file).not.toMatch(/\bexport\s*\*\s*from\s*["']@supabase\/supabase-js["']/i)
  }
})
