// Prints the live definitions held in live-defs.json as SQL (each exactly as read, line endings included), for run.sh.
import fs from 'node:fs'
const defs = JSON.parse(fs.readFileSync(new URL('./live-defs.json', import.meta.url), 'utf8'))
const out = []
for (const [sig, { def }] of Object.entries(defs)) {
  if (sig.startsWith('_')) continue
  if (def.includes('$live$')) throw new Error(`${sig}: quote clash`)
  out.push(`-- ${sig}\ndo $do$ begin execute $live$${def}$live$; end $do$;`)
}
process.stdout.write(out.join('\n') + '\n')
if (process.argv[2] === 'md5s') process.stderr.write(Object.entries(defs).filter(([k]) => !k.startsWith('_')).map(([k, v]) => `${k} ${v.md5}`).join('\n') + '\n')
