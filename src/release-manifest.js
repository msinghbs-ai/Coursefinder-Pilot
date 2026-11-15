// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.6'
export const PACKAGE_VERSION='0.1.428'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'16 Nov 2026',
  title:'Values that were written into the pipeline are now settings (first wave)',
  changes:[
    'Nine new settings on Settings › Pipeline settings, each with the value the pipeline already used, so nothing behaves differently until it is changed with a reason: how long a course or provider counts as verified (Re-read and retry, 30 days); when a failed scholarship scheduler step is tried again (Scholarships, 60 minutes); when a course page is searched for again (Course page search, 7 days); when verification counts as stale on the data quality pages (Health report, 180 days); how long progress snapshots are kept and how young evidence is never purged, and evidence audit columns per run (Storage & retention: 90 days, 7 days, 3); when a provider is checked again for zero-yield pages (Zero-yield pages, 23 hours); and when an English policy plan is worked out again (English policies, 30 minutes).',
    'A scholarship page admitted from its title is next read after Read a scholarship page again after (Re-read and retry), like every other scholarship page; this was the same 90 days written separately.',
    'Values that are technical, not operational, stay in the code and are marked with the reason (for example a 10-minute hand-over lease, or the page size of a list).',
    'Settings tidy-up (v2.16.5): the retired-settings paste file can be run from 29 Nov 2026.'
  ],
  bugFixes:[
    'The website and Zoho APIs are unchanged (checked against their baseline before and after the change).'
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
