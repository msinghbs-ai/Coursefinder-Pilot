// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.370'
export const PACKAGE_VERSION='0.1.297'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'30 Oct 2026',
  title:'Enrichment reliability: source finder within its time limit, one read per page, AI answer limits as settings',
  changes:[
    'Course source finder: choosing the next universities is worked out once per set and finishes well inside the database time limit (it was timing out under load); the same universities are chosen in the same order.',
    'Course page reads: a page is claimed by exactly one read call, so the two reading jobs no longer fetch (and pay for) the same page twice.',
    'University onboarding: each onboarding step follows its own university\'s job.',
    'Adapter builder: a sample capture and a proposal are counted in the worker ledger with their failures, so a working capture no longer reads as "0 of 0" in the health report.',
    'AI reads (worker v0.54.0): every reader\'s answer length is a setting (Settings › Pipeline settings › AI answer limits; defaults are the values used before); an answer cut at its limit holds the whole read instead of failing as broken data, and the cost of every call is recorded, also when a read fails.',
    'Consumer API unchanged (Decision 266).'
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
