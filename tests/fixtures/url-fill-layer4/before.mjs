// Course link fill respects Layer 4 (CF-247 Workstream E, Platform Admin direction 2 Nov 2026 23:24): prints the SQL that rebuilds, from this
// repository's own migration, security.course_url_fill_v1 as it is live before the change (created 24 Oct 2026 in 20261024001000, never edited
// since). run.sh checks the rebuilt md5 against the live one read on 2 Nov 2026.
import fs from 'node:fs'
const sql = fs.readFileSync(new URL('../../../supabase/migrations/20261024001000_cf247_course_url_fill.sql', import.meta.url), 'utf8')
const a = sql.indexOf('create or replace function security.course_url_fill_v1()')
const b = sql.indexOf('\nend $$;', a)
if (a < 0 || b < 0) throw new Error('course_url_fill_v1 not found in 20261024001000')
process.stdout.write(sql.slice(a, b + '\nend $$;'.length) + '\n')
