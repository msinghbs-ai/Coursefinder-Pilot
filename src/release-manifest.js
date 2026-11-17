// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.24'
export const PACKAGE_VERSION='0.1.446'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'17 Nov 2026',
  title:'Layer 1 source induction wizard; Country & category completeness report',
  changes:[
    'Layer 1 › Sources: + Add source now opens a six-step wizard: Country & scheme, Source & licence, Field mapping, Cadence & retention, Dry-run preview, Activation. A draft is saved at each step and can be continued later. Pipeline Operators can prepare a draft; activation is the Platform Admin\'s, with a reason, and the source is saved paused.',
    'Field mapping: map each source field to a platform field and one of eight enrichment categories. AI Auto-Map switches on by itself when the AI mapper is deployed; until then mapping is by hand.',
    'Cadence & retention: the retention entered for a source is recorded only. It does not change what the platform prunes.',
    'Dry-run preview shows rows read, inserts, updates, departures and postcodes under the match share once the source has a reader; before that it says Waiting for a reader.',
    'Platform health: new tab Country & category completeness (Curator and above): field fill by country and category, each Layer 1 source\'s editions, last change and retention, and how long Layer 4 items have waited. The Platform Admin can move a field to another category with a reason.'
  ],
  bugFixes:[
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
