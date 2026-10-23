// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.337'
export const PACKAGE_VERSION='0.1.264'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'24 Oct 2026',
  title:'CRICOS proofs are Australian only',
  changes:[
    'A CRICOS code is an Australian proof and is accepted only for Australian providers, in the admission policy and in every proof list. A New Zealand course page is proved by its NZQA programme code on the page or by its title; a Canadian page by its title. The reader (worker v0.45.0, identity rule v0.6.0) no longer labels any non-Australian page with a CRICOS proof.',
    '406 New Zealand and Canadian course pages that carried an Australian (or wrong-country) proof label were taken back to "page does not match" and are re-verified from their stored copies under the new rule; the 149 fees quarantined at 00:35 re-admit through the normal path once their page is re-bound.',
    'Catalogue › Courses: the CRICOS registered fee column (Tuition Only) is shown only for Australian lists; New Zealand and Canadian lists show the provider\'s international fee.',
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
