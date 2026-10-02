// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.149'
export const PACKAGE_VERSION='0.1.76'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'2 Oct 2026',
  title:'Fetch an area on the course-page sweep; Websites to find; errors with steps',
  changes:[
    'Layer 2 › Fetch an area works on the course-page sweep: for a country, state or university it shows sites mapped or not found, pages found and read, facts admitted and a one-line reading of what is holding it up. Start puts it first in the sweep.',
    'Layer 4 › Websites to find: universities whose website the finder could not confirm, with the search and the pages tried. A website entered here is kept as entered by a person, and the course-page search starts.',
    'Live activity and Layer 2 Action required: each worker error says what to do, often nothing, and when to switch a job off or tell the Platform Admin.',
    'The AI tuition check is given 5 minutes before its caller gives up, and the tuition hand-off picks its pages about six times faster.'
  ],
  bugFixes:[
    'Fetch an area still started the retired Layer 2 pipeline, so a request (La Trobe) would never run; its Open Jobs button did nothing.',
    'Worker error replies gave no steps to resolve them.'
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
