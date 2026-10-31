// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.383'
export const PACKAGE_VERSION='0.1.310'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'31 Oct 2026',
  title:'Health alerts that stay until fixed, and AI spend measured across every route',
  changes:[
    'Platform health: a scheduled job that keeps failing stays on the health list until it has run cleanly, and becomes critical when its last three runs all failed, whatever its schedule. Before, each failure closed itself within the hour, so hourly and daily jobs never escalated (StudySearch SS-014).',
    'Platform health: AI spend over 24 hours now counts every OpenRouter route (enrichment, AI match, entry reads and Layer 3), measured from the credit balance; the daily ceiling (US$14) is a setting. The health detail showed the remaining credit as the day\'s spend; it now names each figure.',
    'Settings › Pipeline settings: four new settings for these thresholds (Platform upkeep).',
    'StudySearch name: test and workflow names no longer use the former name; storage keys, identifiers and history are kept (SS-013).'
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
