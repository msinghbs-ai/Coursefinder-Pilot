// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.197'
export const PACKAGE_VERSION='0.1.124'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'6 Oct 2026',
  title:'Task manager: Qualify adapters and Admit the passing fields',
  changes:[
    'Scheduled jobs › Task manager: long-running admin actions run as tasks worked by the database a slice a minute. Each shows its progress from the database (a refresh loses nothing), who started it and why, and can be paused, resumed or cancelled at the next provider.',
    'Qualify adapters (Operator (adapters) and above): choose a country, state or province, provider kind and adapter state. Every chosen adapter is measured against the admission rules, field by field, with the counts and the reason. Nothing is admitted by the run.',
    'Admit the passing fields (Platform Admin): a separate button on a finished Qualify run admits exactly the fields that passed, through the ordinary admission control, one logged entry per provider. Fields already admitted stay. Values entered by hand are never changed.',
    'Adapter editor › Reading options: numeric start dates, capitalised month names and the one-academic-year rule, each off unless switched on for that adapter (worker v0.17.13).'
  ],
  bugFixes:[
    'Canadian adapters read nothing because nearly every Canadian course is inactive: the builder, preview and apply now read pages of inactive courses too (admission still writes active courses only).'
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
