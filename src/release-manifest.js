// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.316'
export const PACKAGE_VERSION='0.1.243'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'22 Oct 2026',
  title:'No-course providers; Adapter builder course list',
  changes:[
    'Providers › Adapter filter: Not needed: no courses. A provider with no active course shows No courses instead of Create adapter; Has an adapter and No adapter leave it out.',
    'Onboarding stops a provider with no active course (no credits spent) and queues it again by itself once it has one.',
    'Adapter builder › 2.1 Course pages: each page says what is wrong with it (Wrong page, about another course; Old site, refused) instead of Stored, not read yet. The state chips filter the list (Read included), every row can be ticked (Tick all shown), Search again takes the ticked courses, and each row has Add page / Change page. The list pages through every course.',
    'Step numbers stay visible; a finished step adds a Done chip that says what done means.'
  ],
  bugFixes:['Show courses already read did not show them (only the first 200 rows were listed).','Bound pages about another course or on an old site were counted as "Stored, not read yet".']
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
