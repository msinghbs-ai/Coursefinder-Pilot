#!/usr/bin/env node
// CF-247 s980 (S2-Build, Platform Admin 23 Nov 2026 08:47 AEDT): the pre-flight check every new migration passes before any rolled-back live
// dry run, in CI and locally (before a push). No packages; reads git and the files only.
// Usage:
//   node scripts/ci/migration-preflight.mjs --base <git ref> [--live-head <14-digit version>] [file ...]
//     Files are names under supabase/migrations. With none given, the files added between <base> and HEAD are checked.
// Checks, per new file:
//   1. the name is <14 digits>_<lower_snake>.sql and the file exists;
//   2. its version is unique and strictly above every migration on <base> (and above --live-head when given: the live schema_migrations max);
//   3. new files are numbered in order (no two share a version);
//   4. Decision 260: a "Replaces:" and a "Retires:" comment line;
//   5. it can run inside the dry run's transaction: no BEGIN, COMMIT, ROLLBACK or END of its own outside dollar-quoted bodies, no CONCURRENTLY,
//      and not the dry run's own marker.
// Prints one line per finding; exits 1 when any check fails, 0 otherwise ("no new migrations" is a pass).
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const DIR = 'supabase/migrations';
const NAME = /^(\d{14})_[a-z0-9_]+\.sql$/;
const args = process.argv.slice(2);
let base = null, liveHead = null; const files = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--base') base = args[++i];
  else if (args[i] === '--live-head') liveHead = args[++i];
  else files.push(path.basename(args[i]));
}
if (!base) { console.error('migration-preflight: --base <git ref> is required'); process.exit(2); }
const git = (...a) => execFileSync('git', a, { encoding: 'utf8' }).trim();

const baseFiles = git('ls-tree', '--name-only', base, `${DIR}/`).split('\n').map((f) => path.basename(f)).filter((f) => NAME.test(f));
const list = files.length ? files
  : git('diff', '--no-renames', '--name-only', '--diff-filter=A', `${base}...HEAD`, '--', `${DIR}/*.sql`).split('\n').filter(Boolean).map((f) => path.basename(f));
if (!list.length) { console.log('migration-preflight: no new migrations'); process.exit(0); }

const newSet = new Set(list);
const baseMax = baseFiles.filter((f) => !newSet.has(f)).map((f) => f.slice(0, 14)).sort().pop() || '0';
const floor = [baseMax, liveHead && /^\d{14}$/.test(liveHead) ? liveHead : '0'].sort().pop();
const problems = []; const seen = new Map();
for (const f of [...list].sort()) {
  const m = NAME.exec(f);
  if (!m) { problems.push(`${f}: name is not <14 digits>_<lower_snake>.sql`); continue; }
  const p = path.join(DIR, f);
  if (!fs.existsSync(p)) { problems.push(`${f}: file not found`); continue; }
  const v = m[1];
  if (seen.has(v)) problems.push(`${f}: version ${v} is also used by ${seen.get(v)}`);
  seen.set(v, f);
  if (v <= floor) problems.push(`${f}: version ${v} is not above the head ${floor} (main ${baseMax}${liveHead ? `, live ${liveHead}` : ''}); renumber it`);
  const sql = fs.readFileSync(p, 'utf8');
  if (!/Replaces:/.test(sql) || !/Retires:/.test(sql)) problems.push(`${f}: missing a "Replaces:" or "Retires:" line (Decision 260)`);
  const outside = sql.replace(/(\$[A-Za-z_]*\$)[\s\S]*?\1/g, '');
  if (/^\s*(begin|commit|rollback|end)\s*;/im.test(outside)) problems.push(`${f}: opens or ends its own transaction`);
  if (/\bconcurrently\b/i.test(sql)) problems.push(`${f}: uses CONCURRENTLY, which cannot run in the dry run's transaction`);
  if (sql.includes('cf_dryrun')) problems.push(`${f}: contains the dry run's marker`);
}
for (const p of problems) console.log(`migration-preflight: FAIL ${p}`);
if (problems.length) process.exit(1);
console.log(`migration-preflight: ${list.length} new migration(s) pass (above ${floor}): ${list.join(', ')}`);
