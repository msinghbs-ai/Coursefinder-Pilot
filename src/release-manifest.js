// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.200'
export const PACKAGE_VERSION='0.1.127'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'6 Oct 2026',
  title:'Adapters lifecycle workspace, collapsed cards, list-only Task manager',
  changes:[
    'Layer 2 now opens on Adapters: one collapsed row per university holding its test, Qualify and Admit, on/off switch with the consequences stated, read schedule, central pages, fee range and rules, Read pages again, hosted courses, Firecrawl target and history. Bulk Qualify and Admit work on the filtered list, and Admit stays a separate step.',
    'A read cycle (7 to 365 days) can be set per adapter. Pages are re-read on that cycle and a changed page makes new evidence, an unchanged page does not. The default stays 90 days.',
    'Every card on Models & services, Toolsets and the new Adapters screen is collapsed until opened, and stays open or closed for the browser session. Models & services keeps services, keys and limits only.',
    'The Task manager is a list of running, queued and paused tasks with pause, resume and cancel. Qualify starts from Adapters.'
  ],
  bugFixes:[
    'Retired: Layer 2 Overview, Fetch an area, History and Source profiles tabs, and Coverage › Universities (its figures are in the Adapters rows). Source profiles moved to Scrapers & fetchers. Scholarships stays under Layer 2.'
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
