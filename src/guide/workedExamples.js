// CF-247 s931 (Decision 279 §7.3): Help › Platform guide › Worked examples. Each names the screens and what a person sees. Figures are as read at
// release (21 Nov 2026) and are re-checked at each release review (Decision 209). No customer-confidential data.
export const WORKED_EXAMPLES = [
  { key: 'W1', title: 'University-wide entry requirements: Charles Sturt University (CRICOS 00005F)', steps: [
    'Course detail › Entry requirements shows University-wide rule applies for India: the course has no row of its own and the university-wide table covers it.',
    'The Hong Kong row shows In Layer 4 review (1 waiting): the read dropped that row, so it waits for a person while the other seven rows are live (partial admission, 21 Nov 2026).',
    'Entry requirements › Provider entry matrix with Provider = Charles Sturt University, Study destination = AU, Student\'s education country = Hong Kong and Applies to = University-wide shows the row and its quote.',
    'Layer 4 Review › Module / Field = Entry requirements, Source country = Hong Kong: the card shows the dropped row; after Yes the row is Live and the pill becomes the value.'] },
  { key: 'W2', title: 'How scholarships attach to a course', steps: [
    'A scholarship names a course, a study level or faculty, or applies to the whole university (the Notes panel on Scholarships explains each).',
    'A new course shows University-wide rule applies when only a university-wide scholarship covers it, or nothing yet until a rule names it.',
    'Check scholarships for this course on Course detail reads the course against the scholarships the university publishes.'] },
  { key: 'W3', title: 'Central English policy and regulated-discipline holds (Nursing, Medicine)', steps: [
    'The university\'s central English page sets the score for each study level: courses with no own score show University-wide rule applies.',
    'A Bachelor of Nursing at the same university shows In Layer 4 review: regulated disciplines with higher bands are held (course_english, s884 to s886).',
    'The reviewer sees the central page\'s quote beside the course page and decides Yes or No.'] },
  { key: 'W4', title: 'A course with no website or course address', steps: [
    'Course detail shows No official website / course URL on file.',
    'A Curator chooses Add official URL: one address, https only, on the provider\'s own site. It is saved as the course\'s official page and read again.',
    'The read returns values, or a Not stated on institution page pill where the page does not say.',
    'A counsellor who knows the page reports it from Zoho.'] },
]
