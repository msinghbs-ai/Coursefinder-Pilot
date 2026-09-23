// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.82'
export const PACKAGE_VERSION='0.1.9'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'23 Sep 2026',
  title:'Layer 4 review clarity & remembered filters',
  changes:[
    'Layer 4 shows the plain-English reason on every review item, so reviewers can see what happened and what to check without opening it.',
    'Layer 4 remembers each reviewer\'s status and field filters between visits, with a Reset filters button.',
    'Layer 4 status filter uses plain labels (for example "Waiting for review", "Sent back to Layer 3") and adds "All statuses".',
    'Layer 4 review detail summarises the automatic checks; the technical data is available under "Technical detail".',
    'Common screen parts (headings, summary cards, empty states, page navigation) now come from one shared set, so screens look and behave consistently.'
  ],
  bugFixes:[
    'Fewer loading errors at busy times: admission now refreshes only the courses it changes, instead of rebuilding every course.',
    'Layer 4 now lists up to 250 review items, so older items waiting for review no longer drop off the list.',
    'Catalogue filters and search are remembered exactly as before after the move to the shared set.'
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
