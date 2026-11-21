// CF-247 s931 (Decision 279; spec admin docs/design/2026-11-21-layer4-human-ui-and-guide-spec.md §3 and §4): the preservation inventory and where each
// control went. K = kept where it is · M = moved (same control, same server argument, new place) · R = relabelled · N = new. Nothing is deleted and
// nothing is duplicated. Contract test (a) (spec s931) checks that every inventory ID has a map row and every map row an inventory ID.
const range = (p, a, b) => Array.from({ length: b - a + 1 }, (_, i) => `${p}${a + i}`)
export const L4_QUEUE_IDS = ['course_link', 'held_scholarship', 'website_needed', 'pages_not_found', 'too_few_pages', 'nothing_ready', 'central_to_approve', 'onboarding_failed', 'site_down',
  'not_offered', 'fee_check', 'counsellor_report', 'not_on_site', 'no_page_first_run', 'conjoint_first_run', 'aer_review', 'provider_description', 'course_page_needed', 'provider_departure'].map(q => `Q-${q}`)
export const INVENTORY = [...range('L4-V', 1, 7), ...range('L4-F', 1, 15), ...range('L4-B', 1, 10), ...range('L4-C', 1, 10), ...L4_QUEUE_IDS, 'Q-hooks',
  ...range('C-F', 1, 23), 'C-A1', 'C-D1', ...range('P-F', 1, 15), 'P-A1', 'P-T1', 'P-T2', ...range('A-F', 1, 4), 'A-A1', ...range('E-F', 1, 3), 'E-J1', 'S-F1', 'S-F2', 'S-A1', 'G-guides']
const m = (map, to) => ({ map, to })
export const PRESERVATION_MAP = {
  'L4-V1': m('K', 'View › Review by rule (default; Advanced filters › View)'), 'L4-V2': m('M', 'Advanced filters (N) [data-l4-other-views]'),
  'L4-V3': m('M', 'Advanced filters › View › By university'), 'L4-V4': m('M', 'Advanced filters › View › By kind'), 'L4-V5': m('M', 'Advanced filters › View › Grid'),
  'L4-V6': m('M', 'Advanced filters › View › Decided'), 'L4-V7': m('M', 'Advanced filters › View › Groups; Decision bucket › Needs information'),
  'L4-F1': m('M+R', 'Primary row › Module / Field [data-l4-kind]'), 'L4-F2': m('M+R', 'Primary row › Decision bucket; rail groups kept'), 'L4-F3': m('M', 'Primary row › University; Advanced › University list'),
  'L4-F4': m('K', 'By university kind pills [data-l4-pill]'), 'L4-F5': m('M', 'Advanced filters › AER order [data-l4-aer-ready-first]'), 'L4-F6': m('K', 'Why items are held (Layer4HoldReasons)'),
  'L4-F7': m('K', 'Grid › Kind'), 'L4-F8': m('K', 'Grid › Reason contains'), 'L4-F9': m('K', 'Grid › Search'), 'L4-F10': m('K', 'Grid › Order'),
  'L4-F11': m('M+R', 'Primary row › Destination country (Grid keeps its counted pills)'), 'L4-F12': m('K', 'Grid › Provider type'), 'L4-F13': m('K', 'Grid › Saved views'),
  'L4-F14': m('K', 'Descriptions module: ready first and the sample (CdPanel)'), 'L4-F15': m('K', 'Descriptions module: held universities'),
  'L4-B1': m('K+R', 'Rail group row: Preview & Settle Batch'), 'L4-B2': m('K', 'Batch preview: Remove the words & admit n'), 'L4-B3': m('K', 'Batch preview: Re-read n from stored copy'),
  'L4-B4': m('K', 'Batch preview: Queue stored-page fetch'), 'L4-B5': m('K', 'Grid › Grouped decisions'), 'L4-B6': m('K', 'Grid › Clusters'), 'L4-B7': m('K', 'Grid › Export CSV'),
  'L4-B8': m('K', 'Grid › Saved views save'), 'L4-B9': m('K', 'Descriptions module: Open for writing'), 'L4-B10': m('K', 'Batches embed'),
  'L4-C1': m('M', 'Z1 entity; Ref under Technical detail [data-l4-refshow]'), 'L4-C2': m('K', 'Z4 why: Main hold reason + (i) Hint'), 'L4-C3': m('M', 'Z5 Resubmit (rereadable) / recovery action (no stored page)'),
  'L4-C4': m('K', 'Z6 Progress and history (ItemLifecycle)'), 'L4-C5': m('M', 'Z3 source [data-l4-evidence]'), 'L4-C6': m('K', 'Z2 values'), 'L4-C7': m('K', 'Edit & Approve (DescriptionEditAdmit)'),
  'L4-C8': m('M+R', 'Z5 Yes / No / Resubmit + More options [data-l4-choice]'), 'L4-C9': m('K+N', 'Confirm panel + reject chips, Lock this value, AI budget line'), 'L4-C10': m('K', 'Header metrics'),
  ...Object.fromEntries(L4_QUEUE_IDS.map(q => [q, m('R', 'THREE_DECISIONS (src/lib/l4-rules.js) + More options')])), 'Q-hooks': m('R', 'decisionsFor: first allowed confirm/enter = Yes, reject_evidence = No, search_again = Resubmit'),
  ...Object.fromEntries(range('C-F', 1, 23).map(x => [x, m('K', 'Courses filters unchanged')])), 'C-A1': m('K', 'Courses columns, export, presets'), 'C-D1': m('K+N', 'Course detail; empty values show FieldGap pills'),
  ...Object.fromEntries(range('P-F', 1, 15).map(x => [x, m('K', 'Providers filters unchanged')])), 'P-A1': m('K', 'Providers bulk bar'), 'P-T1': m('K', 'Campuses tab'), 'P-T2': m('K', 'Logos & assets, Archived'),
  'A-F1': m('K', 'Provider entry matrix (Provider list: every active provider, s930)'), 'A-F2': m('K', 'Course entry requirements'), 'A-F3': m('K', 'Sources, reads and holds'), 'A-F4': m('K', 'Resolution inspection'), 'A-A1': m('K', 'Entry requirement actions'),
  'E-F1': m('K', 'Courses English filter'), 'E-F2': m('K', 'Coverage › English policies'), 'E-F3': m('K', 'Layer 4 hook kind course_english'), 'E-J1': m('K', 'elr-det-sweep, policy-add-tests'),
  'S-F1': m('K', 'Scholarships list filters'), 'S-F2': m('K', 'Scholarships coverage'), 'S-A1': m('K', 'Notes panel and record folds'),
  'G-guides': m('K+N', 'Platform guide: Filters & badges, Layer 4 guide, Worked examples added'),
}
