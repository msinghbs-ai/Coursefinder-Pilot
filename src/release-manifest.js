// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.396'
export const PACKAGE_VERSION='0.1.323'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'1 Nov 2026',
  title:'One set of words for who changes and who admits; budget gates, freshness and retirement checks',
  changes:[
    'Scheduled jobs › Automations: each automation shows who may change it (PIM Admin or Platform Admin) and how its values get in; the guide\'s Who admits section and the SOPs say the same (UR-08).',
    'Toolsets & limits and the guide: each budget gate says whether StudySearch or the provider refuses, its effective mode, where the live value is and who changes it; a notice in Observe mode says nothing has stopped (UR-10).',
    'Platform health: each check says whether it is from this run, an earlier run or has no result yet, and no result is never shown as OK (UR-11).',
    'Screen use and Automations: a retiring component shows the five retirement checks and its note; removal without a named replacement needs an approved decision (UR-12).',
    'The test register\'s table and narrative are counted in one pass (UR-16).'
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
