// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.240'
export const PACKAGE_VERSION='0.1.167'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'11 Oct 2026',
  title:'Scholarship coverage check and bulk restore',
  changes:[
    'Scholarships \u203a Coverage: each provider measured against its own scholarship listing page \u2014 listed, found, published, missing, our other records and Study Australia records \u2014 with a watch list (the 27 providers checked first) and sign-off.',
    'Opening a provider shows each listed scholarship beside our record: value, linked courses (or \u201call courses\u201d), why it is not published, and Publish, Hold, Withdraw, Release and International actions. Listing pages are found automatically, suggested, or added by hand.',
    'Scholarships published automatically in the last three days are listed for review at the top of Coverage, each with Hold.',
    'Settings and jobs for scholarships are on the Coverage screen; changes no longer ask for a reason.',
    'Providers \u203a Archived: tick several providers or courses and restore them together.'
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
