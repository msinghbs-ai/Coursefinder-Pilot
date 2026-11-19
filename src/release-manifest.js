// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.62'
export const PACKAGE_VERSION='0.1.484'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'20 Nov 2026',
  title:'Layer 4 Edit & Approve for descriptions, and Human Edits & Periodic Audit',
  changes:[
    'Layer 4 Review › Inbox, University and Course description cards: Edit & Approve. The text box starts with the machine text, with the page\'s own words and the official page link beside it and live character, sentence, word and word-list checks. Approve As-Is admits the machine text unchanged; Save Edit & Admit admits your text as human input, locked by hand unless you clear the box, and lists it for review in six months.',
    'Layer 4 Review › Inbox, By kind › University description: Held universities: open for writing lists universities whose reading was held with no machine text; Open for writing makes a card you write by hand from the stored page.',
    'New page Data & Governance › Human Edits & Periodic Audit: My Human Edits (your own) and All Human Edits (Admin Governance, Platform Admin), with Unacknowledged and Due for 6-month re-review counts. Tick edits and choose Acknowledge & Keep Lock, Re-Verify by Machine (a side-by-side comparison with the stored page and the latest machine text; nothing is read again or changed), Edit & Re-Lock, or Release Lock to Machine (Platform Admin).'
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
