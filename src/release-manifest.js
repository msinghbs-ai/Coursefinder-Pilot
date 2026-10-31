// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.384'
export const PACKAGE_VERSION='0.1.311'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'31 Oct 2026',
  title:'Faster health checks, search refresh watch, alerts ready, weekly scorecard',
  changes:[
    'Platform health runs about twice as fast: the scholarship check works out each provider\'s hold once instead of up to three times (median 11.9 s; about 1.4 to 2.3 s in trial runs; same results) (StudySearch SS-014A).',
    'Platform health: a work queue whose job the flag unit paused after idle runs is shown for information while the flag unit switches it on again; it becomes critical only after two hours. It had been raised as critical 116 times in a week (SS-014).',
    'Platform health: new check for search refresh requests. A request waiting past 40 minutes is a warning that names the cause (the refresh gap or another writer); one waiting past 90 minutes, or with its job missing, paused or failing, is critical, with the next step (SS-014B).',
    'Platform health › Alerts: open critical issues become alerts with a quiet period, escalation, reminders and a recovery notice, and failed deliveries are retried. Delivery outside the platform is off until the Platform Admin approves a destination; alerts are recorded here meanwhile. A Platform Admin can acknowledge an issue with a reason and send a test alert (SS-014C).',
    'Platform health › Weekly operational scorecard: targets T1 to T8 measured every morning from existing data, each saying whether it was observed for the whole week or only in part (SS-014D).',
    'Settings › Pipeline settings: new Alerts and Operating targets sections, and two search refresh thresholds under Platform upkeep.'
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
