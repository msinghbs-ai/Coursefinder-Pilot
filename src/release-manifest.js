// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.141'
export const PACKAGE_VERSION='0.1.68'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'2 Oct 2026',
  title:'Live activity',
  changes:[
    'New screen Live activity (under Dashboard): every scheduled job by layer, shown as Running now, Working (what is left, done in 24 hours and about how long to go), Up to date, Paused, Stuck or Failing, with its last run, the worker\'s last result and the next run in Melbourne time. It refreshes every 20 seconds.',
    'Waiting for a person: tiles for fee schedules, scholarships to publish or check, Layer 4 reviews, flagged values and ranking links, each opening its screen.',
    'Scholarship discovery no longer stops when its list runs out: 100 more providers were lined up, the next largest are added every hour, and each run now searches 6 providers instead of 3.'
  ],
  bugFixes:[
    'The release check after each merge failed since v2.15.136 although the site had updated: it cut the download short while looking for the version. It now downloads first, then looks.'
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
