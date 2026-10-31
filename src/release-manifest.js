// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.386'
export const PACKAGE_VERSION='0.1.313'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'31 Oct 2026',
  title:'Faster scholarship hold check; re-read pilot for exhausted course pages',
  changes:[
    'Platform health and the scholarship readers: the check of whether a university is held by the scholarship Firecrawl rules keeps its query plans for the session instead of planning them on every call. Same rules and results; in a trial it took 5.7 s instead of 20.1 s for every provider (StudySearch decision D16).',
    'Course pages: a re-read pilot gives course pages that used all three read attempts one more direct read, at most 25 a day, only 30 days after the last attempt, each page once. No Firecrawl and no AI are used for them; held courses and restricted providers are skipped. The pilot records each outcome and switches itself off if a page is read through Firecrawl or produces Layer 4 review items (decision D13).',
    'Settings › Pipeline settings › Re-read and retry: three settings for the pilot (on, pages a day up to the approved 25, days to wait of at least 30).'
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
