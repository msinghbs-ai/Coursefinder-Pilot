// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.99'
export const PACKAGE_VERSION='0.1.26'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'28 Sep 2026',
  title:'Register changes applied automatically',
  changes:[
    'A CRICOS run first compares the whole register with what was last applied (about 10 seconds) and then applies only new and changed courses. The card shows the register total and how many are new, changed, unchanged and departed.',
    'Courses that leave the register are retired automatically at the end of the run, with an audit record. A large departure (more than 2% of the register) waits for a Platform Admin to approve it on the card.',
    'A retired course that returns to the register is reactivated. A provider whose courses have all left is listed for a person to review as a closure or a merger.',
    'When the weekly check finds a changed register and the record count is within the accepted range, the ingestion now runs automatically (CRICOS and NZQA). The card details show whether automatic ingestion is on.',
    'Duplicate copies of register files were removed after a byte-for-byte check (746 copies, 1.7 GB); every record still points to an identical stored file.'
  ],
  bugFixes:[
    'The course catalogue link index no longer grows with every captured page: links are kept once per provider (447,678 rows reduced to 25,521; the database shrank by 165 MB).'
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
