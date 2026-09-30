// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.116'
export const PACKAGE_VERSION='0.1.43'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'1 Oct 2026',
  title:'Layer 4 batch rules: settle a university’s fees with one rule',
  changes:[
    'Layer 4 has a new tab, Batch rules. When a university words its international fee the same way on every course page, one rule settles all of them.',
    'Type the words that come before the fee (for example “Indicative First Year Fee”), choose the period, and preview exactly which courses would get which fee before saving.',
    'Wordings repeated on many pages with no fee yet are listed, with a one-click Make a rule.',
    'A Pipeline Operator prepares a draft; a PIM Operator approves it, which admits the fees at once and then hourly for newly read pages. Rules can be paused, and every run is logged.',
    'A rule never changes a course that already has a fee or a value entered by hand, and skips pages where the words appear with more than one amount.'
  ],
  bugFixes:[
    'Hundreds of UNSW and Monash fees were sent to Layer 4 one by one although each university words its fee the same way on every page.'
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
