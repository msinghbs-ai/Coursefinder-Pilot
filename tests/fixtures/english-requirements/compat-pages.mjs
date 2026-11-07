// Guards: Platform Admin 6 Nov 2026 09:44 §4 (compatibility gate: previous readers and parser versions) for English requirements: pages whose reading must not change between provider-policy-v0.2.5 and v0.3.0.
// Invented layouts of the shapes the parser reads today (level default, tests as columns, exceptions, bands, by-faculty with one agreed score). No production page.
export const PAGES = {
  'level-default-prose': `## English language requirements\n\nIELTS Academic: undergraduate programs require an overall score of 6.5 with no band less than 6.0. Postgraduate coursework programs require an overall score of 7.0 with no band less than 6.5.\n\nPTE Academic: 58 overall for undergraduate, 64 overall for postgraduate coursework.\n`,
  'level-default-table': `## Minimum English language requirements\n\n| Level | IELTS Academic | TOEFL iBT | PTE Academic |\n|---|---|---|---|\n| Undergraduate | 6.5 (no band less than 6.0) | 79 | 58 |\n| Postgraduate coursework | 7.0 (no band less than 6.5) | 94 | 65 |\n`,
  'exceptions-named': `## English requirements\n\nUndergraduate: IELTS Academic overall 6.5, no band less than 6.0.\nPostgraduate coursework: IELTS Academic overall 6.5, no band less than 6.0.\n\nHigher requirements apply to the Master of Teaching: IELTS Academic overall 7.5 with 7.0 in each band.\n`,
  'faculties-all-agree': `## IELTS Academic\n\n| Faculty | Undergraduate | Postgraduate coursework |\n|---|---|---|\n| Arts | Overall 6.5 (no band less than 6.0) | Overall 7.0 (no band less than 6.5) |\n| Science | Overall 6.5 (no band less than 6.0) | Overall 7.0 (no band less than 6.5) |\n`,
  'no-english': `## About our campus\n\nWe offer more than 200 programs across three campuses. Apply online before the closing date.\n`,
}
