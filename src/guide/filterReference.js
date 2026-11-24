// CF-247 s931 (Decision 279; spec admin docs/design/2026-11-21-layer4-human-ui-and-guide-spec.md §7.1): Help › Platform guide › Filters & badges.
// One entry for every filter on the six screens (Layer 4 Review, Courses, Providers, Entry requirements, English, Scholarships) and one for every
// badge or pill: the screen, its label, what it looks at in plain words, when to use it and who sees it. Reviewed every release with the guide
// (FILTER_REFERENCE_REVIEWED_FOR must equal UI_VERSION); the contract test (spec s931) fails when a filter on a screen has no entry.
export const FILTER_REFERENCE_REVIEWED_FOR = '2.17.0'

const V = 'Viewer and above', C = 'Curator and above'
const e = (screen, label, looks, when, roles = V, id = '') => ({ screen, label, looks, when, roles, id })

export const FILTER_REFERENCE = [
  // Layer 4 Review — primary row (§5.1)
  e('Layer 4', 'Module / Field', 'The queue: which kind of decision is waiting, grouped by module (Course data, Entry requirements, English, Fees, Scholarships, Providers, Descriptions), with how many wait', 'You decide one kind of value at a time', C, 'L4-F1'),
  e('Layer 4', 'University', 'One university\'s waiting items (by its provider id)', 'A university asks about its records, or you work one university through', C, 'L4-F3'),
  e('Layer 4', 'Destination country', 'Where the university is (the countries where admission runs)', 'You work Australian, New Zealand or Canadian universities only', C, 'L4-F11'),
  e('Layer 4', 'Source country', 'Entry requirements only: the student\'s country of prior education on the rows of the read', 'A student from India asks, and you want the reads that carry an India row', C, 'L4-D3'),
  e('Layer 4', 'Decision bucket', 'Ready to decide (a person decides), Needs information (a page, document or value only a person can give), System recovery (the platform re-reads it by itself), All', 'You want only the cards that need your decision today', C, 'L4-F2'),
  // Layer 4 Review — Advanced filters (§5.5)
  e('Layer 4', 'View', 'How the queue is shown: Review by rule, By university, By kind, Grid, Decided, Groups', 'You need a table of rows (Grid) or the last decisions (Decided)', C, 'L4-V2'),
  e('Layer 4', 'University list', 'By university: the universities whose name contains the words typed', 'You look for one university in the list', C, 'L4-F3'),
  e('Layer 4', 'AER', 'Entry requirements of one university: Ready to decide first, or All waiting', 'You want the reads that are complete first', C, 'L4-F5'),
  e('Layer 4', 'Why items are held', 'Entry requirements: the reasons the machine admission held the reads, with counts', 'You want to see why entry tables wait', C, 'L4-F6'),
  e('Layer 4', 'Kind', 'Grid: the queue shown as rows', 'You work one queue as a table', C, 'L4-F7'),
  e('Layer 4', 'Reason contains', 'Grid: the items whose hold reason has these words', 'You look for one hold reason', C, 'L4-F8'),
  e('Layer 4', 'Search', 'Grid: an item or university by its words', 'You look for one record', C, 'L4-F9'),
  e('Layer 4', 'Order', 'Grid: oldest or newest first', 'You work the oldest first, or check the newest', C, 'L4-F10'),
  e('Layer 4', 'Provider type', 'Grid: University, VET / College, School or HEI', 'You work one kind of provider', C, 'L4-F12'),
  e('Layer 4', 'Saved views', 'Grid: shared views (AER Audit Samples, Official URLs, Provider Blockers) and your own', 'You come back to the same set of rows', C, 'L4-F13'),
  // Courses
  e('Courses', 'Study destination', 'The country where the course\'s provider is (where the student would study)', 'You look at one country\'s courses'),
  e('Courses', 'State / Region', 'The state, province or region of the provider', 'You look at one state or region'),
  e('Courses', 'Provider', 'One provider\'s courses (every provider, searched)', 'You look at one university\'s courses'),
  e('Courses', 'University group', 'A group such as the Group of Eight', 'You compare a group of universities'),
  e('Courses', 'Study level', 'The level of study, every level in one list under its group: Pathway, Vocational, Undergraduate, Postgraduate, Other', 'A student asks for one level'),
  e('Courses', 'Field', 'The field of study', 'A student asks for one field'),
  e('Courses', 'Delivery', 'How the course is taught (on campus, online, mixed)', 'A student needs on-campus study'),
  e('Courses', 'Has fee', 'Whether the course has a tuition fee', 'You look for courses with or without a fee'),
  e('Courses', 'Has intake', 'Whether the course has an intake (start date)', 'You look for courses with or without an intake'),
  e('Courses', 'Has English', 'Whether the course has an English requirement', 'You look for courses with or without English requirements'),
  e('Courses', 'Course description', 'Whether the course has a description, and how it was admitted', 'You look for courses with no description'),
  e('Courses', 'Study load', 'Full-time or part-time load', 'A student needs full-time study'),
  e('Courses', 'Empty reason', 'Why a course field is blank, so a blank is not read as "no requirement": not published by the provider, not on the register, online only, waiting to be read, source unavailable. The filter shows the same note when opened', 'You want to know why many courses miss a value'),
  e('Courses', 'International students', 'Whether international students may enrol', 'You look at courses open to international students'),
  e('Courses', 'Has scholarship', 'Whether a published scholarship is linked to the course: the same answer as the course detail and the website', 'A student asks about scholarships'),
  e('Courses', 'Minimum completeness', 'Courses at or above a completeness score', 'You want well-filled courses only'),
  e('Courses', 'Freshness', 'How recently the course was checked', 'You look for courses not checked for a while'),
  e('Courses', 'Status', 'Active, or not active', 'You look for archived or withdrawn records'),
  e('Courses', 'Publication', 'Whether the course reaches the website (its provider\'s Published switch decides)', 'You check what the website shows'),
  // S2-Build s977 (Platform Admin 22 Nov 2026 22:01; Feedback-1 and Feedback-2): the counselling bar Counsellors and Viewers see (Operators and Platform Admins keep every filter above)
  e('Courses', 'Destination country', 'Counselling bar: the country the student would study in; the state, university, level and field lists below it narrow to that country', 'You start a search for a student', 'Counsellor and Viewer'),
  e('Courses', 'University / provider', 'Counselling bar: one university\'s active courses, listed only from the country (and state) chosen; Clear / Reset empties every filter at once', 'A student asks about one university', 'Counsellor and Viewer'),
  e('Courses', 'Field of study', 'Counselling bar: the course\'s field of study, from the fields held for the country and state chosen', 'A student asks for one field', 'Counsellor and Viewer'),
  e('Courses', 'Intake month', 'Counselling bar: courses with an active intake starting in that month (from the start date, or the month the provider names)', 'A student can start only in one month', 'Counsellor and Viewer'),
  e('Courses', 'Intake year', 'Counselling bar: courses with an active intake in that year (the rolling years and the years held)', 'A student plans a start year', 'Counsellor and Viewer'),
  e('Courses', 'Fee from', 'Counselling bar: courses whose international fee (the International fee column) is at least this amount, in the course\'s own currency', 'A student has a budget range', 'Counsellor and Viewer'),
  e('Courses', 'Fee up to', 'Counselling bar: courses whose international fee is at most this amount, in the course\'s own currency', 'A student has a budget limit', 'Counsellor and Viewer'),
  e('Courses', 'Fee order', 'Counselling bar: International fee Lowest to highest or Highest to lowest (courses with no fee last); empty orders by course name', 'A student wants the cheapest or the most expensive first', 'Counsellor and Viewer'),
  e('Courses', 'English test', 'Counselling bar: courses that name this English test (IELTS, PTE, TOEFL and the others held); with the Student score, those asking that score or less', 'A student has a test result', 'Counsellor and Viewer'),
  e('Courses', 'Student score', 'Counselling bar, with an English test: the student\'s overall score; courses asking that score or less are kept', 'You check which courses a student\'s score meets', 'Counsellor and Viewer'),
  // S2-Build s977 (Feedback-1 and Feedback-2): words a counsellor meets on the screens
  e('Glossary', 'PRISMS', 'The Australian Government system that holds every CRICOS provider\'s registered courses for overseas students; StudySearch reads the course list and registered course cost from the CRICOS register it publishes', 'You explain where a CRICOS code or registered cost comes from'),
  e('Glossary', 'QILT', 'Quality Indicators for Learning and Teaching: the Australian Government student and graduate surveys (satisfaction, employment); shown only where the permission to use them is in place', 'A student asks about graduate outcomes'),
  e('Glossary', 'THE', 'Times Higher Education World University Rankings, read from its public ranking table and published with its attribution', 'A student compares universities by ranking'),
  e('Glossary', 'QS', 'QS World University Rankings, applied once a year from the publisher\'s file and published with its attribution', 'A student compares universities by ranking'),
  e('Glossary', 'ARWU', 'Academic Ranking of World Universities (ShanghaiRanking), read from its public ranking table and published with its attribution', 'A student compares research rankings'),
  e('Glossary', 'Publication', 'Whether a record reaches the website: a course follows its provider\'s Published switch', 'You check why a course is not on the website'),
  e('Glossary', 'Empty reason', 'Why a field is blank (not published by the provider, not on the register, online only, waiting to be read, source unavailable), so a blank is never read as "no requirement"', 'You explain a missing value to a student'),
  e('Glossary', 'Zoho / Website feed matched', 'Whether the record\'s latest change reached the Zoho CRM feed or the website feed: the same values both consumers read', 'You check that Zoho or the website shows the latest value'),
  e('Glossary', 'Contacts', 'Provider Contacts: the people and teams at a university for international students, from the university\'s own pages first', 'You need the right person at a university'),
  // Providers (and Campuses)
  e('Providers', 'Type', 'University, VET / College, School, HEI, or Needs type', 'You look at one kind of provider'),
  e('Providers', 'Description', 'Whether the provider has a description', 'You look for providers with no description'),
  e('Providers', 'Description quality', 'How the provider description was judged', 'You look for weak descriptions'),
  e('Providers', 'Description admission', 'How the provider description was admitted (machine, person)', 'You audit how descriptions got in'),
  e('Providers', 'Description source', 'Where the provider description came from', 'You audit the source of descriptions'),
  e('Providers', 'Adapter', 'Whether the provider has an adapter (its reading rules)', 'You look for providers not onboarded'),
  e('Providers', 'On website', 'Whether the provider is in the feed the StudySearch website reads (was "Website feed")', 'You check what the website lists'),
  e('Providers', 'In Zoho CRM', 'Whether the provider is in the Zoho CRM feed (was "Zoho feed")', 'You check what Zoho lists'),
  e('Providers', 'Main campus', 'The providers whose main campus is (or is not) set', 'You check main campuses'),
  e('Providers', 'Primary', 'Campuses: the main campus of each provider', 'You look at main campuses only'),
  // Entry requirements (AER)
  e('Entry requirements', 'Provider', 'One provider\'s entry rows (every active provider is listed, with its live and waiting rows)', 'A counsellor asks about one university'),
  e('Entry requirements', 'Study level', 'The study level the row is for, under the same groups as on Courses; a label the provider publishes sits under the group of the level of the same name (else As published)', 'A student applies at one level'),
  e('Entry requirements', 'Status', 'Live, waiting for your decision, replaced by a newer read, withdrawn or quarantined', 'You check what the website uses (Live)'),
  e('Entry requirements', 'Search', 'Words of the qualification, quote or course', 'You look for one qualification'),
  e('Entry requirements', 'Study destination', 'Where the university is (the countries the platform covers); was "Destination country"', 'You want Australian universities only'),
  e('Entry requirements', 'Student\'s education country', 'Where the student\'s prior qualification is from; was "Source country"', 'A student from India asks'),
  e('Entry requirements', 'Applies to', 'A university-wide row or one course\'s row', 'A course shows no row of its own'),
  e('Entry requirements', 'Kind', 'The kind of requirement (provider minimum, band table, course minimum and so on)', 'You look at one kind of requirement'),
  e('Entry requirements', 'Band', 'The band of a band table', 'You check one band'),
  e('Entry requirements', 'Edition', 'The edition of the source the row was read from', 'You check rows of one edition'),
  e('Entry requirements', 'Intake year', 'The intake year the row is for (this year and the next two are always offered)', 'A student starts next year'),
  e('Entry requirements', 'Read', 'Whether the row came from a read that is still current', 'You look for rows to read again'),
  e('Entry requirements', 'For', 'Who the requirement is for (international, domestic, everyone)', 'You check international requirements only'),
  e('Entry requirements', 'Fetch', 'Sources: whether the source page was fetched', 'You look for sources not yet fetched'),
  e('Entry requirements', 'Read state', 'Sources: whether the stored page was read and why it is held', 'You look for held reads'),
  e('Entry requirements', 'Country of prior education', 'Resolution inspection: the country the five rules resolve for', 'You check what a student from one country sees'),
  // English (Coverage › Attributes › English policies; Course detail English card)
  e('English', 'Show policies', 'English policies: proposed, approved or every policy', 'You approve central English policies'),
  e('English', 'Document type', 'English policies: the kind of page the policy was read from', 'You check policies read from one kind of page'),
  e('English', 'Stage', 'English policies: where the policy is (proposed, approved, applied)', 'You follow a policy to the courses'),
  // Scholarships
  e('Scholarships', 'Audience', 'Who the scholarship is for', 'A student asks for scholarships for them'),
  e('Scholarships', 'Award type', 'The kind of award (fee reduction, payment, prize)', 'A student asks about fee reductions'),
  e('Scholarships', 'Nationality', 'Whether the scholarship states a nationality', 'You look for open scholarships'),
  e('Scholarships', 'Student nationality', 'Scholarships for students of one nationality', 'A student from one country asks'),
  e('Scholarships', 'Also not stated', 'With Student nationality: also the scholarships that state no nationality', 'You want every scholarship the student may apply for'),
  e('Scholarships', 'How to apply', 'How the student applies (automatic, application)', 'A student asks how to apply'),
  e('Scholarships', 'Has description', 'Whether the scholarship has a description', 'You look for scholarships to complete'),
  e('Scholarships', 'Has benefits', 'Whether the benefits are stated', 'You look for scholarships to complete'),
  e('Scholarships', 'Has sponsor', 'Whether a sponsor is named', 'You look for sponsored scholarships'),
  e('Scholarships', 'Has closing date', 'Whether a closing date is held', 'A student asks what closes soon'),
  e('Scholarships', 'Detail read', 'Whether the scholarship page was read', 'You look for pages still to read'),
  e('Scholarships', 'State', 'Published or held', 'You look for held scholarships'),
  e('Scholarships', 'Round', 'Whether the scholarship round is open, closed or not stated', 'A student asks what is open'),
  e('Scholarships', 'Course links', 'How the scholarship links to courses (named course, rule, university-wide)', 'You check why a course shows a scholarship'),
  e('Scholarships', 'Detail recovery', 'Whether a missing detail is being read again', 'You follow a recovery'),
  e('Scholarships', 'Source stale', 'Whether the scholarship page is older than the re-read time', 'You look for pages to read again'),
  e('Scholarships', 'Course', 'Scholarships linked to a course (words of its title)', 'A student names a course'),
  // badges and pills (§6)
  { ...e('Badges', 'In Layer 4 review (N waiting)', 'A value is proposed and a person decides it', 'A counsellor sees why a value is not there yet; Curators open the item'), kind: 'badge' },
  { ...e('Badges', 'University-wide rule applies', 'The course has no value of its own; a university-wide row covers it', 'You explain why a course shows the university\'s value'), kind: 'badge' },
  { ...e('Badges', 'No official website / course URL on file', 'Nothing can be read because no address is held', 'A Curator adds the official address (https, on the provider\'s own site)', V), kind: 'badge' },
  { ...e('Badges', 'Not stated on institution page', 'The page was read and does not state it', 'You tell a student the institution does not publish it'), kind: 'badge' },
  { ...e('Badges', 'Waiting for your decision', 'A row or item waits in Layer 4', 'You find what a person still decides'), kind: 'badge' },
  { ...e('Badges', 'Live', 'The value reaches the website', 'You confirm what students see'), kind: 'badge' },
  { ...e('Badges', 'Replaced by a newer read', 'An older row a newer read replaced', 'You read the history of a value'), kind: 'badge' },
]

/** The entries of one screen, or of every screen; `q` narrows by any words. */
export function filterEntries(screen = '', q = '') {
  const w = String(q || '').toLowerCase().trim()
  return FILTER_REFERENCE.filter(x => (!screen || x.screen === screen) && (!w || `${x.screen} ${x.label} ${x.looks} ${x.when}`.toLowerCase().includes(w)))
}
export const FILTER_SCREENS = [...new Set(FILTER_REFERENCE.map(x => x.screen))]
