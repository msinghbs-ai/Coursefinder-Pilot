// Prints the live definitions held in live-defs.json as SQL (each exactly as read), for run.sh. Bodies are not checked while loading
// (check_function_bodies off), as their dependencies load in any order; run.sh then checks each md5 against the live md5.
import fs from 'node:fs'
const defs = JSON.parse(fs.readFileSync(new URL('./live-defs.json', import.meta.url), 'utf8'))
const out = ['set check_function_bodies = off;']
for (const [sig, { def }] of Object.entries(defs)) {
  if (sig.startsWith('_')) continue
  if (def.includes('$live$')) throw new Error(`${sig}: quote clash`)
  out.push(`-- ${sig}\ndo $do$ begin execute $live$${def}$live$; end $do$;`)
}
out.push('set check_function_bodies = on;')
process.stdout.write(out.join('\n') + '\n')
