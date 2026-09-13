// Canonical browser-visible release authority. Derived release surfaces must import/read this file rather than define their own current version literal.
export const UI_VERSION='2.15.79'
export const PACKAGE_VERSION='0.1.6'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'14 Sep 2026',
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

// Immutable accepted recovery point immediately preceding this candidate.
export const PREVIOUS_ACCEPTED_RELEASE={
  version:'2.15.78',
  packageVersion:'0.1.5',
  date:'11 Sep 2026',
  pilotMain:'7cf5cc72296ca82e6e026606a61f449ede4ead45',
  title:'Governed Scheduled Tasks target builder'
}
