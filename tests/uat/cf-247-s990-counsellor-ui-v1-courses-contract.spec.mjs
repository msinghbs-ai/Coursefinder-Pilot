// Guards: Platform Admin 23 Nov 2026 (v1.1 Counsellor UI, Commit 1: Courses, Save, Compare, State · Campus; MOCKUP-SPEC-AND-RETIREMENT-MAP v1.1 section 4 rules 3, 5, 6 and 10).
// The new build carries only ui-* classes, no !important, no table min-width, no "N regions" pill, and a Compare that cannot show fewer courses than were picked.
import { test, expect } from '@playwright/test';
import fs from 'node:fs';

const dir = 'src/ui-v1/';
const read = f => fs.readFileSync(dir + f, 'utf8');
const css = read('ui-kit.css') + read('tokens.css');
const code = ['CoursesView.jsx', 'CounsellorApp.jsx', 'format.js', 'saved-store.js'].map(read).join('\n');
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
  expect(code).not.toMatch(/\b(Australia|New Zealand|Canada)\b/);
});
