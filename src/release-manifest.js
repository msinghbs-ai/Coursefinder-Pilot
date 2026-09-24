// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.83'
export const PACKAGE_VERSION='0.1.10'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'24 Sep 2026',
  title:'Layer 4 review desk',
  changes:[
    'Layer 4 is now a review desk: a queue on the left and one decision at a time on the right, oldest first; the next item opens after each decision.',
    'Each item shows the course and provider by name, the reason, what is recorded now, what the AI suggested, and the exact words the page shows.',
    'A suggestion (Reject, Approve or Check) is shown for each item, based on simple rules about the page wording. It is never applied automatically.',
    'Links open the provider page, the course page, or a ready-made web search.',
    'A note field is pre-filled from the suggestion, so the reason saved with each decision no longer needs a pop-up.',
    'Less common actions (ask for more evidence, send back to Layer 2 or Layer 3) are under More; technical detail is collapsed.',
    'Status and task filters are remembered per reviewer; the status cards show waiting items, the oldest item against the 7-day target, and suggestion counts.'
  ],
  bugFixes:[
    'The Evidence screen no longer times out and shows no items: its filter options are now prepared in the background.',
    'Review reasons written for developers (for example about Firecrawl or ZenRows) are replaced with plain instructions; the original text stays under Technical detail.',
    'Quotes from pages no longer show web-link formatting.'
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
