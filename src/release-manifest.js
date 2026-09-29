// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.111'
export const PACKAGE_VERSION='0.1.38'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'30 Sep 2026',
  title:'Layer 3 on cheap models only; stronger models only when sent from Layer 4',
  changes:[
    'Claude Sonnet 4.6 is no longer part of any cascade. Intakes run Qwen3 30B, then Claude Haiku 4.5; English runs Qwen3 30B, then Mistral Small 3.2. An answer the last step cannot settle goes to Layer 4.',
    'On Layer 4 Review › Send back to AI, each field has a model choice: the cheap-model cascade, or one named model, including models the cascade no longer uses. A page sent to a named model goes only to that model; if it still cannot be settled, it comes back to Layer 4.',
    'The intake and English checks now run every minute, 40 pages at a time, 8 in parallel.'
  ],
  bugFixes:[
    'Pages where cheaper models found no intake were passed to Claude Sonnet, which agreed in almost every case, spending about US$7 a day for nothing.'
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
