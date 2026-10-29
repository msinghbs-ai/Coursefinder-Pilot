// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.366'
export const PACKAGE_VERSION='0.1.293'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'29 Oct 2026',
  title:'Course evidence overlay, course scholarships back, DP020 entry levels, priority countries, phone drawer and banner, NZ course reading',
  changes:[
    'Course detail: the evidence button opens one evidence timeline in an overlay (full screen on a phone): page discovery and reads, page changes, AI matches and fills, admissions and refusals, fee reader, cross-checks, edits by a person, academic entry requirement reads and scholarship links, each with its date, outcome, source and evidence. The blade no longer embeds "What happened to this course". Escape, the close button and focus return work as in every dialog.',
    'Course detail: the course\'s published scholarships show again (the course read had stopped returning them); an empty list now says why and offers Check scholarships for this course.',
    'Academic entry requirements: a published level label that names several levels counts for each, so a Diploma course finds a provider\'s "Diploma/Associate degrees" rows; the explanation shown is the true one (for RMIT DP020 and India: a band table exists, the course page prints no band).',
    'Countries are offered India, Nepal, Singapore first, then A to Z, in Course detail and every Entry requirements country selector; Course detail remembers the chosen country. Changing country only re-reads the resolution, never starts an AI read.',
    'Phone: tapping an Entry requirements row opens its drawer (a loading row is no longer tappable), the drawer scrolls inside, and the low-credit notice wraps beside its icon instead of sliding under it.',
    'Scholarship links: a scholarship page whose stated levels the reader does not know no longer links every course by field alone; postgraduate research pages map to research levels.',
    'Course-level entry requirements can be read for New Zealand courses whose page carries an already-approved strong identity proof (NZQA code, adapter code, or a person\'s binding); a title-only match is never read.',
    'Consumer API unchanged (Decision 266).'
  ],
  bugFixes:[]
}

// Ordered accepted releases. The first item is the only recovery baseline for a new candidate.
// Historical releases before this central manifest remain retained by the legacy release-history source.
export const ACCEPTED_RELEASES=[
  {
    version:'2.15.79',
    packageVersion:'0.1.6',
    date:'14 Sep 2026',
    pilotMain:'32be4e96a8df342deba3011f9740dc1230a672b2',
    title:'Dispatcher tuning & run metrics',
    changes:[
      'Administration > Scraper Config now separates vendor controls from governed Layer 2 dispatcher tuning.',
      'Admins can compare recent runs using throughput, response/extraction latency, retries, Evidence, field resolution and Layer 2/Layer 3/blocked outcomes.',
      'PIM/Data Admins can tune batch size, run concurrency, stale recovery and paid-attempt limits for subsequent runs with an auditable governance reason.',
      'Running batches retain their immutable policy snapshot; tuning never rewrites work already in flight.',
      'Hourly CourseFinder metrics track dispatcher continuations, provider performance, Evidence and policy snapshots for evidence-based tuning.'
    ],
    bugFixes:[
      'Retains the Layer 2 runner transport safety cap introduced by PR #84: ordinary invocations remain capped at four items and scraper-first invocations at two.',
      'Dispatcher metrics are sanitized and do not expose raw payloads, result/error text, target URLs, Storage paths or provider credentials.',
      'Preserves Layer 1 authority, Layer 3 Evidence/profile/model governance, Layer 4 human authority and separate Search/Publication admission.'
    ]
  }
]

export const RECOVERY_RELEASE=ACCEPTED_RELEASES[0]
