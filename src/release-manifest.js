// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.14'
export const PACKAGE_VERSION='0.1.436'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'16 Nov 2026',
  title:'Course descriptions start with the course\'s own facts; every AI call is recorded as it happens',
  changes:[
    'Course descriptions are written with prompt cdesc-source-grounded-v3: no opening sentence that only introduces the course ("The <course> at <provider> is a ..."); the first sentence starts with a fact the course page prints.',
    'Settings › Settings › Course description and deadline: "rules that earn a second model" decides when a description is asked once more of the next model.',
    'Two telemetry reports, by AI service and model tier and from page discovery to the catalogue, feed the telemetry sheet.'
  ],
  bugFixes:[
    'Every AI attempt is recorded as soon as it finishes, so a worker call the platform stops part-way no longer loses the cost of the attempts it had already made.',
    'A course description declined again records the rule version that declined it (cdesc-machine-v2).',
    'The website and Zoho APIs are unchanged (checked against their baseline before and after the change).'
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
