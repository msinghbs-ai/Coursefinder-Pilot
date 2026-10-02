// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.145'
export const PACKAGE_VERSION='0.1.72'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'2 Oct 2026',
  title:'Fee periods settled automatically; clearer worker errors',
  changes:[
    'Flagged values: a new automatic period check in the Layer 3 fee automation confirms fees whose page wording says per year (for example "1st year indicative fee" or "for 1 yr full-time") or whose course runs a year or less. It runs every 10 minutes; only fees whose page names no period, or another period, stay for a person.',
    'Live activity: each worker error now shows the job that got it, and a Pipeline Operator or Platform Admin can mark an error as seen. It shows again only if it happens again.',
    'Errors already understood (the old automation key, test calls and two compute-limit replies) are marked as seen.',
    'Evidence link indexing works on four pages at a time instead of six, after two runs hit the worker compute limit.',
    'Platform guide: what Layer 4 is, the automatic period check, and Mark as seen.'
  ],
  bugFixes:[
    'About 400 flagged fees waited for a person although their page stated the fee per year, because the check did not recognise wording such as "1st year" or "1 yr full-time".',
    'Live activity listed old and test errors with no way to tell which job they came from or to clear them.'
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
