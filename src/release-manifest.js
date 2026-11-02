// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.413'
export const PACKAGE_VERSION='0.1.340'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'3 Nov 2026',
  title:'Scholarship coverage recovery: every source, every page, one candidate per award',
  changes:[
    'Scholarship discovery no longer stalls behind a long queue, and a site map the site refuses is retried later instead of being marked empty. Every source recorded for a university is mapped, not only its website.',
    'Scholarship listings and catalogues are read page by page; a catalogue counts as complete only when its pagination ends, otherwise it carries on from where it stopped. Each award on a listing or umbrella page becomes one candidate; the same award found on its own page is recognised as a duplicate.',
    'A scholarship page that now redirects to the home page, a listing or a search page is recorded as moved, never withdrawn automatically. Closed rounds and ended scholarships are reported separately.',
    'Scholarship Firecrawl use is limited by the daily scholarship share (the old all-time cap is retired); run sizes and waits are settings. Two proposals ship off for the Platform Admin: scholarships for non-university providers, and evidence-based legitimacy checks in place of the 30-course minimum. A worker outcome check ships paused.'
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
