// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.144'
export const PACKAGE_VERSION='0.1.71'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'2 Oct 2026',
  title:'New Zealand course pages, search and tuition',
  changes:[
    'Fee schedules on Coverage › Attributes now follow the country and university chosen above. Fee schedules are matched by CRICOS code, so choosing New Zealand says there are none and why.',
    'New Zealand course pages are now accepted when the heading is the NZQA title without "(Level N)" and the page shows the same level, or when the page prints the course NZQA number with its label. A page naming the same qualification at another level is not accepted on its title. The 2,584 NZ pages previously rejected are being read again.',
    'The course-page search now covers New Zealand: about 2,900 NZ courses with no page are being searched on their provider own site, by title.',
    'New Zealand tuition is read in NZ dollars and, as in Australia, taken only from a page that prints the course code, then checked by the tested AI model before it is added.',
    'Platform guide updated: how a course page is accepted in each country, and the fee schedule scope.'
  ],
  bugFixes:[
    'Fee schedules ignored the Coverage country, so Australian schedules showed when New Zealand was chosen.',
    'New Zealand courses were never searched for their course page, and correct NZ pages were rejected because NZQA titles end in "(Level N)".'
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
