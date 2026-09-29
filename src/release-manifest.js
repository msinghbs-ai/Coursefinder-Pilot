// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.108'
export const PACKAGE_VERSION='0.1.35'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'29 Sep 2026',
  title:'Layer 3 control: run or pause, daily limits and the model cascade',
  changes:[
    'Layer 3 AI validation now has three tabs: Control, Models and Work queue.',
    'Control shows each task (intakes, English requirements, tuition) with Running or Paused, today\'s spend against its daily limit, the last 24 hours and what is waiting for a person.',
    'Each task shows its model cascade in order, cheapest first: the test score, cost per 1,000 pages, pages settled and passed up in the last 24 hours, and spot-check results.',
    'Platform Admins can pause or run one task or all of them, change the daily limit, switch a step on or off, move it up or down, add a model that has passed its test, or remove one. Every change is logged under Recent changes.',
    'Models lists only the models in use or qualified to be used; models that failed their tests or were never tested are no longer shown.'
  ],
  bugFixes:[
    'The Routing tab showed one model per task and did not show the cascade models (for example Mistral Small and Claude Haiku).',
    'The Work queue repeated a long list of every model profile ever set up.',
    'There was no way to pause Layer 3 or change its models from the admin screens.'
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
