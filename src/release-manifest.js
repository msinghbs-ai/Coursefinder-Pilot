// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.71'
export const PACKAGE_VERSION='0.1.493'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'20 Nov 2026',
  title:'Layer 4 Review: one card shape for every queue, human action apart from system queues, and Preview & Settle Batch',
  changes:[
    'In every Layer 4 queue the rule rail has Human Action Required and System Queues (Auto-Recovering): items an existing rule settles or the platform is recovering no longer sit among the decisions.',
    'Every card has the same shape: the Main hold reason in plain English (machine codes only under Technical detail) and one action bar: admit first, then enter-a-value decisions (Save Edit & Admit) and re-categorise, and the set-aside decisions on the right.',
    'Every rule group has Preview & Settle Batch: it lists the records and, where the queue allows it, settles them with one decision, one reason and a typed confirmation; each record is still decided on its own. Entry requirements, departures and descriptions are never settled as a batch.'
  ],
  bugFixes:[
    'Hold reasons showed machine wording such as "Machine rule … did not admit this: gate_incomplete" or D-R3; the headline is now plain English.'
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
