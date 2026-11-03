// Prints, from this repository's Release C migration (20261103220000, v2.15.427, live), the two definitions workstream C's priority edit reads or
// edits, exactly as created there: security.aer_schedule_country_v1 and security.aer_course_population_v1 (live md5 f6cac5f2357e2091b9884295428341bb,
// read 3 Nov 2026). Bodies are not checked while loading; run.sh checks the md5 against live.
import fs from 'node:fs'
const sql = fs.readFileSync(new URL('../../../supabase/migrations/20261103220000_cf247_aer_scheduled_reading.sql', import.meta.url), 'utf8')
const fn = (name) => { const a = sql.indexOf(`create or replace function ${name}(`); if (a < 0) throw new Error(name); const b = sql.indexOf('$function$;', a); return sql.slice(a, b + 11) }
process.stdout.write(['set check_function_bodies = off;', fn('security.aer_schedule_country_v1'), fn('security.aer_course_population_v1'), 'set check_function_bodies = on;'].join('\n') + '\n')
