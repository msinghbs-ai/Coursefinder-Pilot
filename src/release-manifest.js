// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.143'
export const PACKAGE_VERSION='0.1.70'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'2 Oct 2026',
  title:'Every background job signs in with one-time run passes',
  changes:[
    'The 27 background functions that still used the old automation key (expired 30 Sep 2026) now sign in with one-time run passes, like the other jobs. No function accepts the old key any more, so there is no shared key left to expire or leak.',
    'Functions that call other functions (Layer 2 batch runner, scholarship scope jobs) make a fresh pass for each call.',
    'One allow-list now decides which functions can be given a pass.',
    'All 27 are now deployed from the repository by the deploy workflow; the Ontario college course loader (v0.3.0), which was running without its code in the repository, has been added to it.',
    'Platform guide updated: Budgets and keys, the repeating worker error signal, and the Live activity reading of an old-key error.'
  ],
  bugFixes:[
    'Layer 1 Canada loaders, Layer 2 acquisition and extraction, and scholarship scope jobs would have been refused if run, because they still relied on the expired automation key.'
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
