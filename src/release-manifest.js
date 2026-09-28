// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.101'
export const PACKAGE_VERSION='0.1.28'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'28 Sep 2026',
  title:'Compare shows every dataset by default; Layer 3 AI switched on',
  changes:[
    'Compare: QILT, PRISMS, QS and THE are all on by default and are never greyed out before anything is selected; click a dataset to switch it off. Periods default to the latest available.',
    'Compare in course mode states what each dataset describes: QILT and rankings for each course\'s university, PRISMS for the course, its state and field, or its state.',
    'Layer 3 tuition checks run with a qualified AI model (Decision 160): every answer it gives must be correct, and anything it is unsure of goes to Layer 4.',
    'QILT Student Experience Survey 2025 is the current edition; 2024 is kept for comparison.'
  ],
  bugFixes:[
    'Compare in course mode showed no PRISMS student flow for most courses; it now falls back to the state of the course\'s campuses, as the university view does.',
    'Applying the QILT SES 2025 edition was refused for universities with more than one CRICOS code (Victoria University, Holmes Institute).',
    'The official QS 2025 workbook was read with the region in the country column; the QS parser now finds the real country column and refuses a file that looks like regions.',
    'Layer 3 items sent back from Layer 4 were stuck on a retired AI profile and never rechecked.'
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
