// Guards: Platform Admin 23 Nov 2026 (v1.1 Counsellor UI, Commit 1: Courses, Save, Compare, State · Campus; MOCKUP-SPEC-AND-RETIREMENT-MAP v1.1 section 4 rules 3, 5, 6 and 10).
// The new build carries only ui-* classes, no !important, no table min-width, no "N regions" pill, and a Compare that cannot show fewer courses than were picked.
import { test, expect } from '@playwright/test';
import fs from 'node:fs';

const dir = 'src/ui-v1/';
const read = f => fs.readFileSync(dir + f, 'utf8');
const css = read('ui-kit.css') + read('tokens.css');
const code = ['CoursesView.jsx', 'CounsellorApp.jsx', 'format.js', 'saved-store.js', 'ProvidersView.jsx', 'ScholarshipsView.jsx', 'GuideView.jsx'].map(read).join('\n');
const stripComments = s => s.replace(/\/\*[\s\S]*?\*\//g, '');

test('s990 ui: stylesheet lint (no !important, no table min-width, no legacy tokens or class families)', () => {
  const c = stripComments(css);
  expect(c).not.toMatch(/!important/);
  expect(c).not.toMatch(/table[^{]*\{[^}]*min-width/i);
  expect(c).not.toMatch(/--(cf|m)-/);
  expect(c).not.toMatch(/\.(cf|m|aim|ar|pg|pff|ccol|sch|op|ds|ci)-[a-z]/);
});

test('s990 ui: every class the new screens write starts with ui-', () => {
  const names = [...code.matchAll(/className=(?:"([^"]+)"|\{`([^`]+)`\})/g)].flatMap(m => (m[1] || m[2]).split(/\s+/)).filter(x => x && !x.includes('$') && !x.includes('{'));
  expect(names.length).toBeGreaterThan(20);
  expect(names.filter(n => !n.startsWith('ui-'))).toEqual([]);
});

test('s990 ui: Compare is capped at 4 and shows exactly the courses picked, with the seven practical rows only', () => {
  expect(code).toContain('export const COMPARE_MAX = 4');
  expect(code).toContain('c.length >= COMPARE_MAX ? c : [...c, id]');
  expect(code).toContain('Comparing {ids.length} of {ids.length} selected');
  const labels = [...read('CoursesView.jsx').matchAll(/^  \['([^']+)', d =>/gm)].map(m => m[1]);
  expect(labels).toEqual(['Annual tuition fee', 'Duration', 'State & campus', 'Intakes & exact start dates', 'Academic entry requirements', 'English (IELTS · PTE · TOEFL)', 'Available scholarships']);
});

test('s990 ui: location shows State · campus names, never a bare region count; no operator read or text in the build', () => {
  expect(code).not.toMatch(/\d+\s+regions?|region_count/i);
  expect(code).toContain('+{more} more');
  for (const bad of ['admin_course_edit_read', 'admin_provider_edit_read', 'admin_jobs', 'provider-asset-access', 'Layer 4 Review', 'Dry-Lane', 'pipeline.settings', 'Manual lock']) expect(code).not.toContain(bad);
});

test('s990 ui: lists come from the live lookups (s930), not from lists in the code', () => {
  expect(code).toContain('useLookups()');
  expect(code.replace(/^\s*\/\/.*$/gm, '')).not.toMatch(/\b(Australia|New Zealand|Canada)\b/);
});

test('s990 ui: the Counsellor build has exactly the approved screens (the four of s990 and My reports, s1025 hand-off, s1044) and is the only build rank 2 is given', () => {
  const app = read('CounsellorApp.jsx');
  expect(app).toContain("[['courses', 'Courses'], ['providers', 'Universities & Providers'], ['scholarships', 'Scholarships'], ['reports', 'My reports'], ['guide', 'Guide']]");
  const main = fs.readFileSync('src/mature-main.jsx', 'utf8');
  expect(main).toContain('if((context&&rank===2)||/^#ui-v1');
  expect(main).toContain('if(!context&&!error)return');
});

test('s990 ui: Scholarships reads only counsellor_scholarships_list; Providers shows Not recorded and the REQ-116 empty state; the guide types no version or count', () => {
  expect(read('ScholarshipsView.jsx')).toContain("supabase.rpc('counsellor_scholarships_list'");
  expect(read('ScholarshipsView.jsx')).not.toMatch(/new Date\(\)/);
  expect(read('ProvidersView.jsx')).toContain('Not recorded');
  expect(read('ProvidersView.jsx')).toContain('No partner contacts recorded for this provider');
  expect(read('GuideView.jsx')).not.toMatch(/v2\.\d+|\b\d{2,}[,\d]*\s+(courses|providers|scholarships)\b|reviewed for/i);
});

test('s990 follow-up: ui-v1 imports only its own two stylesheets and keeps saves on the server, not in browser storage', () => {
  const dir = 'src/ui-v1'
  const files = fs.readdirSync(dir).filter(f => /\.(jsx?|css)$/.test(f))
  for (const f of files) {
    const t = fs.readFileSync(`${dir}/${f}`, 'utf8')
    for (const m of t.matchAll(/(?:import\s+(?:[^'"]*from\s+)?|@import\s+(?:url\()?)['"]([^'"]+\.css)['"]/g)) expect(['./tokens.css', './ui-kit.css'], `${f} imports ${m[1]}`).toContain(m[1])
    expect(t, f).not.toMatch(/localStorage/)
  }
  const store = fs.readFileSync(`${dir}/saved-store.js`, 'utf8')
  for (const fn of ['saved_courses_read_v1', 'saved_course_toggle_v1']) expect(store).toContain(fn)
  expect(fs.readFileSync(`${dir}/ProvidersView.jsx`, 'utf8')).toContain('provider_partner_contacts_v1')
})
