// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.341'
export const PACKAGE_VERSION='0.1.268'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'24 Oct 2026',
  title:'Plain error messages, a steady version, honest completeness',
  changes:[
    'An error now shows as one plain line with a short reference (for example "The database took too long to answer… (ref AB3K7Q)"); the full detail is kept for the Platform Admin. A message belongs to the screen that raised it and no longer follows you to the next screen.',
    'When a newer version has been released while this window was open, a notice offers a reload, so the top bar and the screens never disagree about the version.',
    'Coverage › "Fully complete courses" counts the attributes the platform can read; the 20–24 Oct rows explain why they read 0.',
    'Consumer API unchanged (Decision 266).'
  ],
  bugFixes:[
    'The official-page admission job had failed on every run since 23 Oct because a rule tried to apply a plain http:// course address; such an address now waits for a person and the job runs again.',
    'Raw database wording (function names, CONTEXT lines, vendor and job names) no longer appears in Platform health, Layer 2/3 or Scheduled jobs.'
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
