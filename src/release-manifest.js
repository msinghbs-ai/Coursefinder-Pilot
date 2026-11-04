// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.471'
export const PACKAGE_VERSION='0.1.398'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'4 Nov 2026',
  title:'Layer 4 shows what happened after every action',
  changes:[
    'Every Layer 4 action returns a result confirmed by the server, kept on the card through Refresh: for example "Recovery queued — 12:17 AEDT", "Recovery refused — unchanged evidence and reader", "Recovery completed — still held under E13" or "Recovery completed — replacement read ready for review", with its audit reference.',
    'Each card has a Progress block: first entered Layer 4, status, last reviewer action, last recovery and its result, next step and time waiting, with an expandable event history (requests, reads with start and finish times and attempt numbers, validations, supersessions and decisions) in AEDT/AEST.',
    'While a recovery runs the card updates by itself; a replacement read is linked and Approve opens only when the completeness gates pass.',
    'A re-read on an unchanged stored copy that was already refused is no longer recommended or run; a repeated click returns the existing request or Human input needed item instead of starting another.'
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
