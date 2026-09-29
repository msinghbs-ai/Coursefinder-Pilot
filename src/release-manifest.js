// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.104'
export const PACKAGE_VERSION='0.1.31'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'29 Sep 2026',
  title:'Complete-coverage sweep: every provider site read on a schedule',
  changes:[
    'Course coverage shows a new stage, "Found on verified page (awaiting admission)": the value is on the course\'s own page, confirmed by the CRICOS course code or the exact course title, and waits for the approved admission rule.',
    'The coverage sweep runs continuously: provider site maps are read (free) or mapped, course pages are matched one-to-one and read with robots.txt respected, and pages are kept as evidence.',
    'Providers with no website on record are found by web search and accepted only when the site shows the provider\'s own CRICOS provider code.',
    'Fee schedules and the UQ English tables are checked for changes monthly (weekly October to December); a changed document is flagged for review, never applied automatically.',
    'Layer 3 tuition checks can run up to 15,000 a day (spend ceiling US$5 a day).'
  ],
  bugFixes:[
    'Course coverage: selecting a count to list the courses failed (provider name column).',
    'The Data Quality scope selector no longer shows on Course coverage, where it had no effect.'
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
