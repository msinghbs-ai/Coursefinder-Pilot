// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.424'
export const PACKAGE_VERSION='0.1.351'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'3 Nov 2026',
  title:'Release A — orchestration: plan steps never finish with work left; page-proof lane; per-field backlog',
  changes:[
    'A plan step whose lane is held (budget, idle or unavailable) stays held with what is left, its checkpoint, its reason and when it resumes, carries on by itself when the lane has room, and ends failed with a reason after 24 hours without progress; a plan is never done while a step still has work. The idle guard no longer pauses a lane while a task has work waiting for it. Applies to Find course pages, scholarship scans and provider fill.',
    'Steps that ended done with work left in the last 7 days (18 steps, 314 items) are marked failed with their reason so automatic re-planning picks them up; a check raises an integration issue if any step ends done with work left again.',
    'Courses whose page is not yet proven are routed by a new twice-hourly feed to the existing page-finding engines: a free re-try of the course\'s candidate addresses when its stored page was refused, paid course-page search only when switched on, and left alone when a Layer 4 decision or a lock applies. Each course is tried a limited number of times and again only when its inputs change.',
    'Platform health › Pipeline yield shows each field\'s backlog: waiting on Layer 4, not stated by the official source, with a verified stored page, or needing a page; with processed and admitted counts over 24 hours and 7 days and a forecast only when there is a measured rate.'
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
