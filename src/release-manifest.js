// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.4'
export const PACKAGE_VERSION='0.1.426'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'15 Nov 2026',
  title:'One scheduler for reports and caches, one runner for admission rules, and quieter scheduled jobs',
  changes:[
    'Reports and screen caches: a new job, rollup-scheduler, works out every minute which of 26 report and cache refreshes are due on their own schedules and runs them one after another, frequent ones first. It started in shadow on 15 Nov 2026: it records what was due while the old jobs still run them. Settings › Pipeline settings › Rollup scheduler.',
    'Admission rules: a new runner in three lanes (admission-rule-runner, -b and -c) takes over 20 field-specific admission rule jobs on their own schedules, with a time budget and a circuit breaker per rule: a rule that fails 3 times in a row is skipped for a back-off that doubles from 15 minutes up to 4 hours, and a Platform health issue is raised until its next good run. It starts in shadow. Settings › Pipeline settings › Admission rule runner.',
    'Shadow rule (Platform Admin 15 Nov 2026 22:36): a scheduler like these runs in shadow for 24 hours; when its dispatches match the old jobs, the old jobs are switched off. They are dropped by a paste file after the 14-day retention window.',
    'Search refresh: each run may take up to Settings › Pipeline settings › Website API › Search refresh: time limit for one run (5 minutes); it failed about one run in five on the database\'s two-minute limit.',
    'Four busy jobs start on quieter minutes with the same number of runs an hour (course page AI match preparation, link refresh, the website reference bundle and course description admission). Eight switched-off jobs are retiring.'
  ],
  bugFixes:[
    'Course description proposals that can no longer be approved are found without the full description check, so the hourly job no longer times out.',
    'The website and Zoho APIs are unchanged (checked against their baseline before and after each change).'
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
