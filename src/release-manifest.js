// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.86'
export const PACKAGE_VERSION='0.1.508'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'23 Nov 2026',
  title:'Counselling filters on Courses; API usage in one table',
  changes:[
    'Courses: Counsellors and Viewers see seven counselling filters: Destination country, State or region, University / provider (with Clear / Reset), Study level, Field of study, Intake month and year, and Tuition fee and English (fee range, Fee order Lowest to highest or Highest to lowest, an English test with the student\'s score, Has scholarship). Each list narrows to the destination chosen. Operators and Platform Admins keep every filter.',
    'Settings › API usage: one compact table of the keys, each once, with calls for 7 and 30 days, error rate, 95th percentile, last used and Issue or Rotate. Legacy keys fold under one line; traffic detail and the switch controls fold below.',
    'Provider detail: View active courses opens Courses filtered to that university. Provider Contacts has Clear / Reset.',
    'Help › Platform guide › Filters & badges: a glossary of the words on the screens (PRISMS, QILT, THE, QS, ARWU, Publication, Empty reason, the Zoho and Website feeds, Contacts).'
  ],
  bugFixes:[
    'Courses: a list filtered by state or region and sorted (for example Australia, New South Wales by International fee) opens in under a second instead of 3 to 7 seconds.',
    'Courses: with a state chosen, the City column names that state\'s campus cities only (a course with campuses in Victoria and South Australia no longer shows Adelaide on a Victoria search).'
  ]
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
