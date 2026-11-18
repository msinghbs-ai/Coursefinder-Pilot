// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.39'
export const PACKAGE_VERSION='0.1.461'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'18 Nov 2026',
  title:'Operations: Task manager, health checks, staging and audit trail',
  changes:[
    'Platform health › Health checks: four more checks: Dispatchers, Boost admission and spend, Layer 4 backlog, and Guardrails (G1 every running job catalogued, G3 the consumer API unchanged).',
    'Platform health › Storage & retention: Staging tables shows each staging table, its rows and size, and what the nightly staging retention would remove.',
    'Evidence: an Audit trail button lists the latest dispatcher runs, the Boost model qualifications and the latest Layer 4 decisions, with who, when and why.'
  ],
  bugFixes:[
    'Scheduled jobs › Task manager opens again instead of stopping on a statement time-out (ref KEW72U); 254 entry requirement readings that could never finish were closed with their reason.',
    'Health checks no longer raise a critical or stuck alarm for a queue a person paused with a recorded reason, or for a job a dispatcher now runs.'
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
