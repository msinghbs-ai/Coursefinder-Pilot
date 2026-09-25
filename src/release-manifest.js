// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.94'
export const PACKAGE_VERSION='0.1.21'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'26 Sep 2026',
  title:'Clearer operations screens',
  changes:[
    'Each Layer screen shows its title once; the Layer header is now a slim bar with its purpose and refresh button.',
    'Jobs shows only columns that have values, a single "Completed" status and no empty mode badges, and the table fits the screen.',
    'Layer 4: the queue scrolls in its own column and the decision panel stays in view; batch history loads its details only when opened.',
    'Layer 3 states plainly when AI interpretation is paused and why.',
    'UQ fees described on UQ\'s fee explanation ("Approximate yearly cost of full-time tuition") are admitted by the approved provider rule, and each course keeps one current tuition fee.'
  ],
  bugFixes:[
    'Developer labels ("Canonical governance · governed browser RPC", "CF-205", "CF-206", "CF-245", "CF-093") replaced with plain titles.',
    'The "Suggested reject" card no longer implies every rejection is about fees.'
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
