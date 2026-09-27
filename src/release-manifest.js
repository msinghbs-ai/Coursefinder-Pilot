// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.98'
export const PACKAGE_VERSION='0.1.25'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'27 Sep 2026',
  title:'Layer 1 runs in the background with live progress',
  changes:[
    'Layer 1 register runs now continue in the background after you start them. You can close the page, and the database restarts a stalled run automatically within a minute.',
    'Each Layer 1 card shows live progress: items done out of the total, pace, time remaining, when it last updated and which batch is being worked on.',
    'Temporary errors from a source (for example HTTP 502) are retried automatically up to five times, with increasing waits. The card shows the retry and the error.',
    'A failed run shows the real error on the card and offers Resume from the item where it stopped. A completed run shows new, changed and unchanged counts and how long it took.',
    'Register files that have not changed are stored once and reused, instead of being saved again for every batch.'
  ],
  bugFixes:[
    'Run now no longer fails with a duplicate request error when a run of the same source failed earlier that day.',
    'Run progress was overstated for Australian runs (for example 207,824 processed out of 25,978). Progress now counts items actually reached.',
    'A source whose last run failed is now counted under Attention.',
    'The QS rankings card shows the ingested 2026 edition (1,501 rows) again, titled with its year; the 2027 edition, not yet available from the publisher, shows as pending.'
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
