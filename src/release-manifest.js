// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.87'
export const PACKAGE_VERSION='0.1.14'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'24 Sep 2026',
  title:'Layer 4 approvals fixed',
  changes:[
    'Approving a tuition fee in Layer 4 (single, edited or in a batch) now records the fee, and it appears in search and the website API.',
    'Approve is offered only when a fee is proposed and already marked per year; otherwise the item asks you to use Edit and approve, where you choose the frequency.',
    'The Edit and approve form has its own note, pre-filled; no pop-up asks for a reason.',
    'The floating "OpenRouter API Key" button is removed; the key is managed in Administration > Environment migration.'
  ],
  bugFixes:[
    'Approve and Edit and approve for tuition fees previously did nothing: the backend refused them, and the error appeared only at the top of the page.',
    'Errors now appear in the review panel, where you are working.',
    'While editing, the other decision buttons are hidden, so actions no longer appear twice.',
    'Items with no proposed fee are no longer labelled "Suggest approve".'
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
