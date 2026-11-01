// SS-014 P2 fixtures: the health check (security.platform_health_check_v1) cannot be rebuilt from this repository (edits between 21 and
// 31 Oct 2026 were made live without a migration), so the fixture holds only its coverage page reading rule, with those lines exactly as
// live (run.sh checks each line's md5 against the live line read on 2 Nov 2026). This script reads the migration's own edit pairs for the
// health check and prints:
//   node hc-edit.mjs check <signature>   SQL giving, for that function, how often each old text occurs and the md5 after the edits
//                                        (read-only; the same query, run on production, gave the after md5 the migration checks)
//   node hc-edit.mjs variant <before> <after>   the migration with the health check's md5s set to the fixture skeleton's
import fs from 'node:fs'
const MIG = new URL('../../../supabase/migrations/20261102040000_cf247_ss014_d14_monitoring_accuracy.sql', import.meta.url)
const m = fs.readFileSync(MIG, 'utf8')
const head = "select pg_temp.edit_once('security.platform_health_check_v1(boolean)', "
const a = m.indexOf(head); const e = m.indexOf('array[1, 1]);', a) + 'array[1, 1]);'.length
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
  const md5s = call.match(/'([0-9a-f]{32})', '([0-9a-f]{32}|__HC_AFTER__)'/)
  process.stdout.write(m.replace(call, call.replace(md5s[0], `'${x}', '${y}'`)))
} else throw new Error('usage: check <signature> | variant <before> <after>')
