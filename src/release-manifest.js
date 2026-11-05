// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.482'
export const PACKAGE_VERSION='0.1.409'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'5 Nov 2026',
  title:'Intake dates: fair turns for every university, current calendars only, and course evidence before a date',
  changes:[
    'The intake-dates job now gives every university with eligible rows a turn: rows are taken round by round (25 a university a round, a setting), the university waiting longest first, so one large university no longer takes the whole hourly batch. The batch size is unchanged.',
    'An old calendar edition (its latest proved teaching start is in an earlier year) is set aside with the reason and no longer supplies period names or dates; equivalent official labels such as Term 1 and Teaching period T1 are matched as one period.',
    'A date is admitted only when the course page states the intake as the course\'s own offering (never a personal account or a past year), and a month-only match needs the course\'s intake months to follow the university\'s main calendar; otherwise the row is held with its reason.',
    'The Platform Admin can withdraw an intake value the process admitted, with a reason: only the fields it set are reverted, the history is kept, the course\'s intakes are held by the existing lock, and the Website API v2 source is checked.'
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
