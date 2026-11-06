// Guards: v2.15.486 acceptance defect (Platform Admin acceptance 6 Nov 2026): the Course catalogue Columns panel was clipped because its classes
// (.cc-bar, .cc-panel, .cc-count) were also defined in src/data-quality.css, which the production build loads for every page.
// A screen stylesheet that owns a class prefix must be the only stylesheet that defines classes with it, and may extend only the shared classes it
// names here. Runs before every build (package.json prebuild) and in tests/uat/cf-247-course-catalogue-columns-contract.spec.mjs.
import fs from 'node:fs'
import path from 'node:path'

export const OWNED = [
  // file, its prefix, the shared classes it may extend (never define anew)
  { file: 'src/catalogue-columns.css', prefix: 'ccol-', extends: ['m-table-wrap', 'm-col-resize', 'tone-success', 'tone-warning'] },
]
const strip = css => css.replace(/\/\*[\s\S]*?\*\//g, '')
// class names used in selectors (not in property values)
export function selectorClasses(css) {
  const out = new Set()
  for (const m of strip(css).matchAll(/([^{}]+)\{/g)) for (const c of m[1].matchAll(/\.(-?[_a-zA-Z][\w-]*)/g)) out.add(c[1])
  return out
}
function cssFiles(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(d => d.isDirectory() ? cssFiles(path.join(dir, d.name)) : d.name.endsWith('.css') ? [path.join(dir, d.name)] : [])
}
export function collisions(root = '.') {
  const problems = []
  const all = cssFiles(path.join(root, 'src'))
  for (const o of OWNED) {
    const own = selectorClasses(fs.readFileSync(path.join(root, o.file), 'utf8'))
    for (const c of own) if (!c.startsWith(o.prefix) && !o.extends.includes(c)) problems.push(`${o.file}: .${c} does not use the prefix ${o.prefix} and is not a listed shared class`)
    for (const f of all) {
      if (path.resolve(f) === path.resolve(root, o.file)) continue
      const other = selectorClasses(fs.readFileSync(f, 'utf8'))
      for (const c of own) if (c.startsWith(o.prefix) && other.has(c)) problems.push(`${path.relative(root, f)} also defines .${c} (owned by ${o.file})`)
      for (const c of other) if (c.startsWith(o.prefix)) problems.push(`${path.relative(root, f)} defines .${c}: the prefix ${o.prefix} belongs to ${o.file}`)
    }
  }
  return [...new Set(problems)]
}
if (process.argv[1] && process.argv[1].endsWith('verify-css-class-collisions.mjs')) {
  const p = collisions()
  if (p.length) { console.error('css-classes: FAIL\n' + p.join('\n')); process.exit(1) }
  console.log(`css-classes: PASS — ${OWNED.map(o => `${o.file} (${o.prefix})`).join(', ')} defines no class another stylesheet defines`)
}
