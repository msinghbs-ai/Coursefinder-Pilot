// Decision 5 E-7/E-8 fixtures: public.admin_adapter_builder cannot be rebuilt from this repository (it has changed live without a complete
// migration), so the fixture holds a skeleton (builder-skeleton.sql). This script reads the migration's own edit pairs for it and prints:
//   node builder-edit.mjs check <signature>      SQL giving, for that function, its md5, how often each old text occurs and the md5 after the
//                                                edits (read-only; the same query, run on production, gave the before and after md5s the
//                                                migration checks)
//   node builder-edit.mjs variant <before> <after>   the migration with admin_adapter_builder's md5s set to the skeleton's
import fs from 'node:fs'
const MIG = new URL('../../../supabase/migrations/20261102070000_cf247_budget_enforcement_and_watchdog.sql', import.meta.url)
const m = fs.readFileSync(MIG, 'utf8')
const head = "select pg_temp.edit_once('public.admin_adapter_builder(text,jsonb)', "
const a = m.indexOf(head); if (a < 0) throw new Error('admin_adapter_builder edit not found')
const e = m.indexOf('array[1, 2]);', a) + 'array[1, 2]);'.length
const call = m.slice(a, e)
const pairs = [...call.matchAll(/\$o\$([\s\S]*?)\$o\$,\s*\$n\$([\s\S]*?)\$n\$/g)].map(([, o, n]) => [o, n])
if (pairs.length !== 2) throw new Error(`expected 2 edit pairs, found ${pairs.length}`)
const [, , mode, x, y] = process.argv
if (mode === 'check') {
  const d = `pg_get_functiondef('${x}'::regprocedure)`
  let rep = d
  for (const [o, n] of pairs) rep = `replace(${rep}, $o$${o}$o$, $n$${n}$n$)`
  const counts = pairs.map(([o]) => `(length(${d}) - length(replace(${d}, $o$${o}$o$, ''))) / length($o$${o}$o$)`)
  process.stdout.write(`select md5(${d}) before_md5, ${counts.map((c, i) => `${c} edit${i + 1}_times`).join(', ')}, md5(${rep}) after_md5;\n`)
} else if (mode === 'variant') {
  const md5s = call.match(/'([0-9a-f]{32})', '([0-9a-f]{32})'/)
  process.stdout.write(m.replace(call, call.replace(md5s[0], `'${x}', '${y}'`)))
} else throw new Error('usage: check <signature> | variant <before> <after>')
