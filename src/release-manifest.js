// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.90'
export const PACKAGE_VERSION='0.1.17'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'25 Sep 2026',
  title:'Queue relief and complete release history',
  changes:[
    'Layer 3 no longer refuses correct fees just because a page is saved with link formatting (about 60% of waiting tuition items). Takes effect once the updated AI check is deployed and re-qualified.',
    'Items refused only for that reason are suggested "Send back" in Layer 4, and can be sent back in batches, once the updated AI check is active.',
    'Official course link items are suggested Reject for exit awards and study abroad or exchange programmes, which have no course page, and research degrees are pointed to the provider\'s research-degree page.',
    'Jobs shows only the counts a job actually recorded, instead of rows of empty cells.',
    'Release notes: every release is kept. The release notes list now fills in all past releases, and "All release notes" opens a searchable history page.',
    'A guarded "Deploy edge functions" workflow deploys functions straight from the repository.'
  ],
  bugFixes:[
    'Send back to AI check (Layer 3) now really re-checks tuition items; before, returned items left the queue without being re-checked.',
    'Release notes for v2.15.79 to v2.15.88 disappeared from the list when a newer release shipped; they are shown again.',
    'An out-of-date automated test was corrected.'
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
