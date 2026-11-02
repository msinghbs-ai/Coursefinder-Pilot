// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.408'
export const PACKAGE_VERSION='0.1.335'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'2 Nov 2026',
  title:'Academic entry requirements: catalogue-first coverage and gap queue',
  changes:[
    'Coverage & completeness › Academic entry requirements now measures four things against every eligible Australian and New Zealand provider in the catalogue (1,476): sources discovered, requirements extracted, requirements admitted through Layer 4, and requirements a counsellor can see. Each shows its numerator and denominator.',
    'A gap queue lists every eligible provider with its status (not discovered, source held, reader failed, awaiting Layer 4, active, course-level only), groups repeated faults under one root cause, and reopens a gap that comes back. The provider drill-down shows the next action and owner.',
    'An hourly check (off until switched on) compares the catalogue with what is held, from the database only, with no page reads.',
    'A weekly AER report section for Monday 08:00 (off until switched on): e-mail by the existing alert route, a copy kept in the repository and shown on this screen.'
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
