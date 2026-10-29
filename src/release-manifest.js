// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.374'
export const PACKAGE_VERSION='0.1.301'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'30 Oct 2026',
  title:'Approve except keeps active rows whose replacement is left out; adapter measures role check',
  changes:[
    'Layer 4 › Inbox, entry requirements (decision D4): under Approve except an active row is replaced only when you approve a new row with the same identity; an active row whose new reading you leave out stays active and unchanged, and a row the new read does not carry stays active. The excluded row records the active row it would have replaced, and the decision event lists what was replaced and what was kept.',
    'Two approved rows with one identity, or an approved row already active elsewhere for the provider, hold the whole decision ("Held (decision D4): … nothing was changed"); the item stays waiting. On a course page that already has active rows, Approve except is held; use Approve all rows or Reject.',
    'Consumer API unchanged (Decision 266).'
  ],
  bugFixes:['Adapter measures (Layer 2/3) checked its role in a way that never applied, so any signed-in user could read it; it now requires the PIM Admin or Platform Admin (rank 5 or above), as originally intended (decision D6).']
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
