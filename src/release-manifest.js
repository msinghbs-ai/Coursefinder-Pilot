// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.423'
export const PACKAGE_VERSION='0.1.350'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'3 Nov 2026',
  title:'Enrichment lanes held separately; the gap queue resumes and takes only readable work; paused jobs stay paused',
  changes:[
    'Work on stored evidence never waits for paid page fetching: scholarship pickers take items with a stored copy first while the scholarship lane is held, and every worker call records its lane outcome (done, idle, budget held, source limit, failed, switched off) with the reason. Platform health › Pipeline yield shows the lanes now.',
    'The standing gap queue scans active courses in slices from a saved point, resumes after a stop, and only creates items for courses whose page the reader accepts; the rest are counted as waiting for page proof instead of being skipped one by one.',
    'A job a person or a governed restore switched off (Settings › Pipeline settings › jobs held off) is never switched back on by the idle recheck and its worker is never called.'
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
