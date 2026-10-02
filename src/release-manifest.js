// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.147'
export const PACKAGE_VERSION='0.1.74'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'2 Oct 2026',
  title:'Layer 2: actionable overview, daily progress, old pipeline retired; Canada data admission',
  changes:[
    'Layer 2 › Overview: Action required lists only Layer 2 jobs that are failing or stuck and workers sending back errors, each with what it means, what to do and a button to Live activity or Scheduled jobs.',
    'Layer 2 › History: Daily progress by country (official page, English, intakes, tuition), with the change from the day before, replaces the old run and fetch lists.',
    'The older provider-reading pipeline is retired: its 7 scheduled jobs are paused (not removed) and its history kept.',
    'Canada: each university’s own site is found by name and accepted only on its own .ca site whose home page names it or prints its DLI number; course pages are matched by exact title and read in Canadian dollars.'
  ],
  bugFixes:[
    'Layer 2 Overview showed Action required with no button or guidance (alerts from the retired pipeline).'
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
