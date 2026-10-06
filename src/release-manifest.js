// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.199'
export const PACKAGE_VERSION='0.1.126'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'6 Oct 2026',
  title:'Read pages again, Firecrawl runs, adapter Apply and central pages are tasks',
  changes:[
    'Read pages again (one university or the ones ticked), a Firecrawl run, Apply on an adapter and Attach page for a central page now start a task from the same button: the button shows the task\'s progress from the database with a Cancel, the Task manager lists it while it runs, and its result lands under Scheduled jobs › Jobs.',
    'A Firecrawl run can be paused and resumed from the Task manager (the run stops and continues). Read pages again, Apply and a central page read can be cancelled but not paused.',
    'Retired: the Universities panel\'s own re-read request list, and the Firecrawl Runs table with its Start, Stop and Continue buttons. Firecrawl\'s call log stays in the support report.'
  ],
  bugFixes:[
    'The person who started a task now shows on the task detail as well as the list.'
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
