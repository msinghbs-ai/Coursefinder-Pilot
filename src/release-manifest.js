// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.306'
export const PACKAGE_VERSION='0.1.233'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'20 Oct 2026',
  title:'Layer 2/3 Build & enrich, and fewer screens',
  changes:[
    'Layer 2 is now Layer 2/3 Build & enrich. Operations comes first: each stage (find the website, find course pages, build the adapter, admit and enrich, scholarships) shows the universities working on it, waiting for it and stopped for a person, with the jobs behind it (pause, resume, run now), the onboarding pace and settings, and the central pages waiting for approval across universities.',
    'Universities joins the old Onboarding and Adapters tabs: one row per university with its journey stage, why it stopped and what waits in the Inbox; open a row for Retry or Stop, its journey and its adapter. The Adapter builder opens from a row.',
    'Retired, with their addresses redirected: Layer 4 Review queue, AI could not decide and Websites to find (now Inbox kinds), Coverage › Counsellor reports (closed in the Inbox as Fixed or Not changed), Scheduled jobs › Priority queue (the search cap moved to Models & services › Toolsets & limits) and the Scrapers & fetchers page (now Models & services › Fetchers).',
    'Layer 4 › Inbox: providers that left the register are decided here (closed, merged with a successor, or still operating), and Decided lists the decisions taken.',
    'Platform health › Screen use (Platform Admin): how often each page and tab is opened, so unused screens can be retired on evidence.'
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
