// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.91'
export const PACKAGE_VERSION='0.1.18'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'25 Sep 2026',
  title:'Simpler menu and provider fee rules',
  changes:[
    'Jobs and Scheduled Tasks are now one menu item, Jobs & Schedules, with two tabs.',
    'Approved provider fee rules: where a provider officially states what its published fee means, that rule settles the fee frequency. First rule: UQ program pages show the indicative annual international fee, as UQ states on its own site.',
    'Fees admitted under a provider rule are recorded with the rule\'s wording (for example "indicative annual").',
    'Each saved web page now records which tool fetched it, so acquisition tools can be changed without losing traceability.',
    'Scheduled Tasks states that historical jobs are never reset or replayed; running a schedule again creates a new run.'
  ],
  bugFixes:[
    'A duplicate row of Layer 1 to 3 shortcuts was removed from Scheduled Tasks.',
    'The Dashboard button "Open Review Queue" now reads "Open Layer 4", matching where it goes.',
    'Automated checks: the remaining out-of-date tests were fixed.'
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
