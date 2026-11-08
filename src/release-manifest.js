// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.494'
export const PACKAGE_VERSION='0.1.421'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'8 Nov 2026',
  title:'Operations by lane, Firecrawl allowance and course description review capacity',
  changes:[
    'Layer 2/3 Operations now shows every automated lane stage by stage: what moved in the last 24 hours, what waits for a person, and what each job did. A green job, a stage transfer and published data are kept apart.',
    'Models & services > Firecrawl shows the plan allowance, live remaining credits, the last sync, the reserved floor and the room above it, and daily use by group. It is read only and shows credits only.',
    'Layer 4 Inbox, Course description pill: shows review capacity and a review pack ordered by university, with objective flags on each item. Nothing is decided for you.',
    'The course search queue no longer says tomorrow\'s share when the cause is a hold on course-link work.',
    'Firecrawl: the 100,000-credit monthly plan size and the reserved floor for course-link work are now settings, changed with a reason.'
  ],
  bugFixes:[
    'Intake dates are read correctly across a year change and are not admitted again after a withdrawal.',
    'Fee figures that look implausible are held for a person, and a decided fee is not asked about again (ships off).',
    'A provider description that was held is read again when the stored copy of the page changes.',
    'English requirements show where courses are still missing English, and repeat planning pauses for an onboarding that has stalled.',
    'Scholarship coverage states are clearer and retries are limited. New spend paths ship switched off; the consumer API is unchanged.'
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
