// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.88'
export const PACKAGE_VERSION='0.1.15'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'24 Sep 2026',
  title:'Layer 4 team and forecast',
  changes:[
    'Layer 4 has a Team and forecast view: waiting items, arrivals and decisions per day, how long items have been waiting, and a forecast of when the queue clears (or a warning that it is growing).',
    'Managers (PIM Admin and above) see who decided what, with median time per decision and outcomes; everyone else sees only their own figures.',
    'Task filters show how many items are waiting, for example "Tuition fee (282)".',
    'Tuition items with no proposed fee show Edit and approve as the main action, so the fee can be entered and approved.'
  ],
  bugFixes:[
    'Tuition items with no proposed fee showed only Reject and More; Edit and approve is back.',
    'Approving a tuition fee from the app no longer fails with "UPDATE requires a WHERE clause".',
    'Course details no longer time out: provider rankings now load in a fraction of the time.'
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
