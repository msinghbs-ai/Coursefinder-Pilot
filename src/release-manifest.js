// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.289'
export const PACKAGE_VERSION='0.1.216'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'18 Oct 2026',
  title:'Adapter builder guide',
  changes:[
    'Layer 2 › Adapter builder: a guide at the top shows every step (Done, Running by itself, Your turn, Optional, Later), the one next thing for you with a button that goes to it, and what is running by itself now. The page refreshes every 15 seconds while work runs.',
    'Steps that run by themselves say so: contacts (1.2), central pages (1.3) and course-page search (2.1) show a spinner and “nothing to press” while they run. Contacts and central pages are marked optional for the adapter; central pages are done in parallel with step 2.',
    'After a website change the result says everything restarts by itself; Fill in from website is only needed to read again now.'
  ],
  bugFixes:['Platform Admin 18 Oct 2026 22:03: the builder flow after a website change was unclear (no indication of the next step; course-page search ran without saying so).']
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
