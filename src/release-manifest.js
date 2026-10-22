// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.321'
export const PACKAGE_VERSION='0.1.248'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'23 Oct 2026',
  title:'Course sources: the platform finds each university\'s course list itself',
  changes:[
    'Layer 2/3 › Course sources (new tab): the course source finder looks for each university\'s own course list by itself. It maps the site with Firecrawl (one credit), checks the result against the address pattern of the course pages already found, and falls back to the site maps and the usual list pages. Each university shows what was found and why, what was tried, and its course and programme lists. The countries it works on and the list addresses it tries are changed here, with a reason.',
    'Courses from the university\'s own programme list: where the only official source lacks degrees (Quebec), programmes are read from the university\'s list, their level is taken from the credential the page names, and they are created hidden. They show on the website only after a Platform Admin approves that university\'s programme list on Course sources.',
    'A course list can be read by Firecrawl map or from a site map with an address pattern, for course finders that are search apps.'
  ],
  bugFixes:['24 courses bound to scholarship, events, policy or e-book pages were unbound so the page matcher finds their real course page.']
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
