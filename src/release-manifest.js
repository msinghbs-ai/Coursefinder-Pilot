// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.402'
export const PACKAGE_VERSION='0.1.329'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'2 Nov 2026',
  title:'A course page is linked only when it is proved to be the course\'s own; quieter, more accurate monitoring',
  changes:[
    'Course pages and official links: every way a page is linked (searches, site maps, award links, re-checks) now checks that the page is this course\'s own: provider, code, level, award and credit points, campus, audience, handbook year, and whether the page is shared. A page that fails is refused, never linked again, and sent to Layer 4 › Course link once.',
    'Award within a course: a Graduate Certificate or Diploma is linked to its Master\'s page only where that page names the award, or a person recorded the link. Holds and page blocks now apply to award links too.',
    'AI reading uses only pages proved to be the course\'s own.',
    'Where a course holds several official pages and none is marked primary, the course\'s own page is shown when it passes the check (42 courses); no course loses its shown page.',
    'Health and Queue watch count what the readers actually take, so pages of hidden universities no longer raise a false \'stopped\' alert; a daily search limit shows as \'Paused: daily cap\'.',
    'AI course matching pauses itself after 30 empty runs as intended (about 1,400 fewer calls a day).'
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
