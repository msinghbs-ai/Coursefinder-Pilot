// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.121'
export const PACKAGE_VERSION='0.1.48'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'1 Oct 2026',
  title:'Reference sources and editable Key dates',
  changes:[
    'Reference data › Key links is now Reference sources: every third-party site the platform refers to (Hotcourses, Study Australia, regulators, ranking publishers, search and social sites), each with a domain, an on/off switch and ticked uses.',
    'The platform reads this list instead of fixed patterns in code: sites marked Never a university website are skipped when finding a university’s site, sites marked Never a course page are refused as course pages, scholarships sourced only from a placeholder site need a university page before publishing, and Ranking imports takes its publisher addresses from here.',
    'Names, addresses and purpose can be edited in place, and Check now (or Check all) shows whether each site is reachable. Adding or retiring a site, or changing how it is used, needs a reason and is logged.',
    'Key dates shows the list first. Edit a title, date, kind, precision, source or warning in place, cancel a date, or add one from a short form. Dates show as dd/mm/yyyy.'
  ],
  bugFixes:[
    'Rankings and statistics still pointed to Layer 1 Register for ranking imports; it now points to Reference data › Ranking imports.'
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
