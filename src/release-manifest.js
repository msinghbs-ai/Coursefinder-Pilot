// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.372'
export const PACKAGE_VERSION='0.1.299'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'30 Oct 2026',
  title:'Entry requirements review path: Approve except, Platform Admin decisions, bulk Read again on the newest copy',
  changes:[
    'Layer 4 › Inbox shows entry-requirement (AER) items as their own kind with every row, its quote, the source and the stored copy. The Platform Admin can Approve all rows, Approve except (tick the rows to leave out, with one reason) or Reject the read. Excluded rows stay visible as "excluded by approve except", with the item and reviewer named; they are never admitted, superseded or re-read automatically.',
    'Entry-requirement items are decided one at a time: generic bulk and batch decisions skip them and say how many were skipped. Only the Platform Admin admits or rejects them; Curators can read them and keep their editing in Catalogue › Entry requirements.',
    'Bulk Read again (entry requirement sources) reads only the newest stored copy of each source; older copies keep their history and their waiting items are closed as superseded. It now refuses any signed-in user who is not the Platform Admin.',
    'Consumer API unchanged (Decision 266).'
  ],
  bugFixes:['The bulk Read again role check never applied inside its function, so any signed-in user could call it; it now requires the Platform Admin.']
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
