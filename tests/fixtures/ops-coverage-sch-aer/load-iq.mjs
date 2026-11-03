// Prints, from this repository's migration 20261102120000 (the integration queue, unchanged since), the two queue tables and
// security.integration_issue_upsert_v1 exactly as created there, for run.sh. Workstream C opens its investigations through that function.
import fs from 'node:fs'
const sql = fs.readFileSync(new URL('../../../supabase/migrations/20261102120000_cf247_integration_queue.sql', import.meta.url), 'utf8')
const between = (start, end) => { const a = sql.indexOf(start); if (a < 0) throw new Error(`missing: ${start}`); const b = sql.indexOf(end, a); if (b < 0) throw new Error(`no end: ${end}`); return sql.slice(a, b + end.length) }
process.stdout.write([
  between('create table if not exists pipeline.integration_issues (', 'revoke all on sequence pipeline.integration_issue_events_id_seq from public, anon, authenticated;'),
  between('create or replace function security.integration_issue_upsert_v1(p jsonb', 'end $function$;'),
].join('\n') + '\n')
