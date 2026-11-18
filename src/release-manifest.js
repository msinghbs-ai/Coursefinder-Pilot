// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.46'
export const PACKAGE_VERSION='0.1.468'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'19 Nov 2026',
  title:'Course detail: shorter and role-aware',
  changes:[
    'Course detail: the Description pipeline is folded by default for Editors and Platform Admins (open it to see the stages, checks, runs and Tasks that held this course). Counsellors and Viewers do not see it.',
    'Course detail: Related insights & funding (QILT and PRISMS context) is folded by default for everyone; open it when you need it.',
    'Course detail: scholarships are shown once, in the course\'s Scholarships section (three, then Show all (N) scholarships). The second Scholarships & funding card in the insights is gone; the Provider detail keeps its own.'
  ],
  bugFixes:[
    'Course detail: Check scholarships for this course and other task buttons are hidden for Counsellors and Viewers, and in Preview as Counsellor or Viewer.'
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
