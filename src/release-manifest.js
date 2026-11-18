// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.43'
export const PACKAGE_VERSION='0.1.465'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'18 Nov 2026',
  title:'Layer 4 clusters; City metrics fit a narrow pane',
  changes:[
    'Layer 4 Review › Inbox › Grid › Clusters: choose a kind and the waiting items are grouped by university, reason and the same quote (numbers, spacing and links ignored). Open a cluster to see its items, export the clusters, or tick clusters and settle them with one choice, one reason and a typed confirmation. Each item is decided exactly as on its own card, at the rank it needs, and logged.',
    'Entry requirements, campus localities, provider departures and Human input needed are inspect only in Clusters: they are decided one at a time. A choice that needs a value or a page is never offered for a whole cluster.',
    'A cluster that keeps coming back is the case for a Boost or reader rule: export it so the rule can be written into the worker and tested.'
  ],
  bugFixes:[
    'Destination data › City metrics & costs: a long measure name (climate_annual_rainfall_mm) now wraps, so the table fits a narrow window without scrolling sideways.'
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
