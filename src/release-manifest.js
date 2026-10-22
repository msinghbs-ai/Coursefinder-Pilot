// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.319'
export const PACKAGE_VERSION='0.1.246'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'22 Oct 2026',
  title:'Progress watchdog for the work queues',
  changes:[
    'Platform health › Work queues: every 15 minutes each enrichment queue (course page search, discovery and reading, AI page matching, course list pages, companion pages, fee reader, central pages, onboarding, enrichment plans, scholarships) gets one state: Moving, Waiting for budget, Stuck, Failing, Out of toolset, Nothing left to try, Done or Paused, with what is waiting, how fast it finishes and the time to finish.',
    'Stuck and Out of toolset are sent to the Platform Admin\'s phone and email (again after 12 hours if still so); Done and Nothing left to try go in the daily report. Stuck, Failing and Out of toolset also open an issue on Health checks that closes by itself.',
    'Fixed by itself, and logged: items that gave up on a passing error (time-out, busy server, cut-off AI answer) get one more try, at most once a week each and never while a tool is out. Course data is never changed by the watchdog.',
    'All thresholds are settings (queue_watch.*) on Settings › Pipeline settings.'
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
