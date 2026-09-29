// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.110'
export const PACKAGE_VERSION='0.1.37'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'30 Sep 2026',
  title:'Full control from the admin screens: automations, sending work back to the AI, and scholarship publishing',
  changes:[
    'Scheduled jobs has a new first tab, Automations: every job the platform runs on a schedule, grouped by area, with a plain name, what it does, how often it runs (times in IST), its last run and the last 24 hours.',
    'Platform Admins can pause or resume one automation or a whole area, run one now, change how often it runs, and change the batch size where it works in batches. Every change is logged.',
    'Layer 4 Review has a new tab, Send back to AI: review items the Layer 3 AI could not settle, grouped by reason. A Platform Admin can send a group, or all items for a field, back to Layer 3 to go through the model cascade again, and retry Layer 3 work that failed.',
    'Each Layer 3 task card has a Send back to AI button for the items it raised for review.',
    'Scholarships has a new Publishing tab: what is published, what is ready to publish and why the rest is not. A Platform Admin can publish the ready list with an approval note, hold a scholarship with a reason, and release a hold.'
  ],
  bugFixes:[
    'Scheduled automations, moving review items back to Layer 3 and publishing scholarships could only be done in the database.'
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
