// Guards: CF-247 decision D6 (Platform Admin 30 Oct 2026 08:45; admin decision paper §11.3): public.admin_adapter_measures enforces its original boundary (rank 5 or above, 'Platform Admin or Operator required') for every API caller using JWT claims instead of current_user, which never fired inside the security definer function; a direct owner session without claims still runs it; service_role and anonymous callers are refused; grants unchanged; md5-guarded; nothing else in the function changed
// Design adopted as admin decision paper §11.3. Live proof: rolled-back dry run on 30 Oct 2026 (anon, curator rank 3, rank 4 refused; rank 5, Platform Admin, owner session allowed; service_role refused). G2 is guarded by s32, G3 by s57, housekeeping by s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const DIR = 'supabase/migrations'
const FILE = fs.readdirSync(DIR).find((f) => /^[0-9X]{13,14}_cf247_d6_adapter_measures_role_check\.sql$/.test(f))
const m = fs.readFileSync(`${DIR}/${FILE}`, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const OLD = [...m.matchAll(/\$o\$([\s\S]*?)\$o\$/g)].map((x) => x[1])
const NEW = [...m.matchAll(/\$n\$([\s\S]*?)\$n\$/g)].map((x) => x[1])
const archive = fs.readFileSync('supabase/migrations-archive/20261005001390_cf247_adapter_measures.sql', 'utf8')

const LIVE_MD5 = 'b1417eafad2aa7a9ed11e3af65e848e8'
const NEW_MD5 = '8ad49afc3fdc03a94dda380404fa7a60'
const NEW_CHECK = "if (auth.uid() is not null or coalesce(auth.role(), '') <> '') and (auth.uid() is null or coalesce(v_rank, 0) < 5) then raise exception 'Platform Admin or Operator required' using errcode = '42501'; end if;"

// The corrected predicate, modelled: claims present (a user id or any role claim) means an API caller, who must be signed in with rank 5 or above.
// uid: auth.uid() (the claim sub); role: auth.role() (the claim role, null without claims); rank: security.current_role_rank() for that uid.
const refused = ({ uid, role, rank }) => (uid != null || (role ?? '') !== '') && (uid == null || (rank ?? 0) < 5)
// The old predicate as it really evaluated: current_user inside the security definer function is always the owner, postgres.
const CURRENT_USER_IN_DEFINER = 'postgres'
const oldRefused = ({ uid, rank }) => CURRENT_USER_IN_DEFINER !== 'postgres' && (uid == null || (rank ?? 0) < 5)

const CALLERS = [
  { who: 'anonymous API caller', uid: null, role: 'anon', rank: 0, refused: true },
  { who: 'signed-in curator (rank 3)', uid: 'b9ba5d27-d01d-419b-a95e-ee777445455b', role: 'authenticated', rank: 3, refused: true },
  { who: 'signed-in pipeline operator (rank 4)', uid: 'u-4', role: 'authenticated', rank: 4, refused: true },
  { who: 'signed-in rank 5 (pim_admin)', uid: 'u-5', role: 'authenticated', rank: 5, refused: false },
  { who: 'Platform Admin (rank 6)', uid: '63ba56cb-48d4-4169-98c2-7c4d1f72925b', role: 'authenticated', rank: 6, refused: false },
  { who: 'service_role over the API, no user', uid: null, role: 'service_role', rank: 0, refused: true },
  { who: 'direct owner session (migration, SQL editor), no claims', uid: null, role: null, rank: 0, refused: false },
]

test('md5-guarded: the live definition is checked before anything changes; the one edit applies exactly once to the 5 Oct check line', () => {
  expect(FILE).toBeTruthy()
  expect(m).toContain(`select pg_temp.edit_n('public.admin_adapter_measures(uuid[])', '${LIVE_MD5}', array[`)
  expect(m).toContain("if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;")
  expect(m).toContain("if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;")
  expect(m).toMatch(/\], array\[1\]\);/)
  expect(OLD).toHaveLength(1)
  expect(NEW).toHaveLength(1)
  // the old text is the archive's line 10, verbatim (two-space indent as pg_get_functiondef keeps it)
  const line10 = archive.split('\n')[9]
  expect(line10).toContain("if current_user <> 'postgres' and (auth.uid() is null or coalesce(v_rank, 0) < 5)")
  expect(OLD[0]).toBe(line10)
})

test('the corrected check: claims decide, rank 5 and the message kept, no current_user test left; the query body is untouched', () => {
  const newLines = NEW[0].split('\n')
  expect(newLines).toHaveLength(2)
  expect(newLines[0]).toMatch(/^ {2}-- D6 \(30 Oct 2026\): /)
  expect(newLines[1]).toBe(`  ${NEW_CHECK}`)
  expect(newLines[1]).not.toMatch(/current_user|session_user/)
  expect(newLines[1]).toContain('coalesce(v_rank, 0) < 5')                 // not 4 (broader) and not 6 (narrower)
  expect(newLines[1]).toContain("'Platform Admin or Operator required' using errcode = '42501'")
  // the function is edited, not rewritten: no whole-body create of it, so the query below the check stays byte-identical
  expect(code).not.toMatch(/create\s+or\s+replace\s+function\s+public\.admin_adapter_measures/i)
  // the post-check pins the result and refuses any current_user test left in the function
  expect(m).toContain(`if md5(v_def) <> '${NEW_MD5}' then raise exception 'D6 post-check: admin_adapter_measures md5 is % (expected ${NEW_MD5})', md5(v_def); end if;`)
  expect(m).toContain(`if position($c$${NEW_CHECK}$c$ in v_def) = 0 then`)
  expect(m).toContain("if v_def ~ 'current_user\\s*<>' then raise exception 'D6 post-check: a current_user test is still in the function'; end if;")
})

test('direct API callers: anonymous, signed-in unauthorised and service_role refused; rank 5, Platform Admin and the owner session allowed', () => {
  // the modelled predicate is the one written into the migration
  expect(NEW_CHECK).toContain("if (auth.uid() is not null or coalesce(auth.role(), '') <> '') and (auth.uid() is null or coalesce(v_rank, 0) < 5) then raise")
  for (const c of CALLERS) expect(refused(c), c.who).toBe(c.refused)
  // the defect: the old check refused nobody, so every signed-in user and service_role read the measures
  for (const c of CALLERS) expect(oldRefused(c), c.who).toBe(false)
  // tightening only: nobody refused before is allowed now
  for (const c of CALLERS) if (oldRefused(c)) expect(refused(c), c.who).toBe(true)
})

test('grants restated unchanged; the owner path is checked after the edit; the migration changes nothing else', () => {
  for (const g of ['revoke all on function public.admin_adapter_measures(uuid[]) from public, anon;', 'grant execute on function public.admin_adapter_measures(uuid[]) to authenticated;']) {
    expect(archive).toContain(g)
    expect(m).toContain(g)
  }
  expect(code).not.toMatch(/\b(grant|revoke)\b[^;]*\bservice_role\b/i)
  expect(m).toContain("or has_function_privilege('anon', 'public.admin_adapter_measures(uuid[])', 'execute') then")
  expect(m).toContain("if public.admin_adapter_measures(array[]::uuid[]) <> '[]'::jsonb then raise exception 'D6 post-check: the owner session no longer runs the measures'; end if;")
  expect(m).toContain("comment on function public.admin_adapter_measures(uuid[]) is 'CF-247 Decision 254: ")
  // only this function: no other object created, altered or written
  const stmts = code.toLowerCase()
  expect(stmts.match(/create or replace function/g)).toEqual(['create or replace function'])   // the pg_temp helper only
  expect(stmts).toContain('create or replace function pg_temp.edit_n(')
  for (const w of ['drop ', 'delete from', 'truncate', 'insert into', 'update ', 'alter ', 'cron.schedule', 'create table', 'create index']) expect(stmts).not.toContain(w)
})
