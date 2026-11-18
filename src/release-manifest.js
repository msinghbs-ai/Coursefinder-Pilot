// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.41'
export const PACKAGE_VERSION='0.1.463'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'18 Nov 2026',
  title:'Operations screens: dispatchers first, storage now, evidence by origin',
  changes:[
    'Scheduled jobs › Automations starts with the three dispatchers (Reports and caches, Admission rules, Coverage lanes): their lanes, runs and failures in 24 hours, last run, and how many legacy jobs each replaced.',
    'Retired legacy jobs are hidden from Automations and its counts until you tick Show retired legacy jobs.',
    'Platform health › Storage & retention starts with Storage now: database size and its 7-day change, staging growth in 7 days, whether nightly staging retention prunes or only reports, and its last run.',
    'Evidence starts with Where evidence comes from: each type in plain words under what writes it (coverage lanes, Boost page text, scholarships, registers, earlier Layer 2 reads); one click filters to it. Dispatcher runs and Layer 4 audit opens the Audit trail or the audit samples grid.'
  ],
  bugFixes:[
    'Platform health › Open issues: links named Work queues now say Queues & yield, the tab they open. Every issue and check link is named from the menu.'
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
