// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.17.0'
export const PACKAGE_VERSION='0.1.509'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'24 Nov 2026',
  title:'One look across the admin: Coverage, Layer 1, Layer 2/3 and the catalogue table',
  changes:[
    'Platform health, Scheduled jobs, Coverage (course, field, telemetry, entry requirements, ETA, link refresh), Layer 1 Register, Layer 2/3 Operations, Reference sources and the Scholarship journey now use the same look as Courses, the Dashboard and the Guides.',
    'The catalogue table (Courses, Providers, Scholarships and Entry requirements) uses the same look. Column widths you saved carry over.',
    'Every empty list shows the same empty-state pill.',
    'Layer 4 Review: a card shows its main facts and keeps a hook\'s long detail behind one "Technical detail" toggle, so a queue reads faster.'
  ],
  bugFixes:[
    'Coverage: the notice you dismiss stays dismissed for the visit instead of relying on browser storage.'
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
