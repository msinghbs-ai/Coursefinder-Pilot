// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.283'
export const PACKAGE_VERSION='0.1.210'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'16 Oct 2026',
  title:'API usage console for Zoho API v2 and Website API v2',
  changes:[
    'Operations \u203a API usage: for each API (Zoho API v2, Website API v2) the calls, success rate, failures, bandwidth sent and the last call, for the last 24 hours, 7 days or 30 days.',
    'Each key: who uses it, on or off, last call and last success, calls, failures (client errors, rate limited, server errors, with the last error), bandwidth, average and largest reply, times, and when it was last rotated.',
    'Full loads and deltas: the last completed full load (when, how long, pages, items, load size), deltas, CSV exports and searches per key.',
    'Statistics refresh every day at about 00:20 Melbourne time; Refresh statistics now gives fresh figures at once.',
    'Platform Admin: Rotate a key (the new key is shown once and not stored; the old key keeps working for the hours you choose, 24 by default in Settings), End old key, Switch off and on. Every change is listed under Key changes.'
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
