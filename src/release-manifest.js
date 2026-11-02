// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.409'
export const PACKAGE_VERSION='0.1.336'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'2 Nov 2026',
  title:'Integration queue: every detected problem becomes one tracked issue',
  changes:[
    'Platform health › Integration queue lists every detected problem as one issue with a stable fingerprint, its affected entities, evidence, severity, owning workstream and status from Detected to Closed. A repeat updates the same issue; a problem that returns after closure reopens it as a regression; an issue closes only with production verification evidence.',
    'An automatic check (off until switched on) runs twice an hour and turns failed job runs, stuck adapter drafts, duplicate or regenerated Layer 4 items, stale leases, search leaks, unexpected spend and course links written while a review is pending into issues. A critical issue raises one alert and one recovery notice.',
    'A deployment check records the migration and function fingerprints after each release and opens an issue on any mismatch.',
    'The current operating mode (Active Remediation or Steady-State Monitoring) is shown and recorded when it changes.'
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
