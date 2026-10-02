// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.155'
export const PACKAGE_VERSION='0.1.82'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'3 Oct 2026',
  title:'Bulk English policy approval; search budget; Canada and New Zealand course pages',
  changes:[
    'Coverage › Attributes › English policies: tick several and choose Approve selected or Reject selected. Select all that can be approved leaves out documents most course pages disagree with.',
    'Approving one document of a university closes its other waiting documents of the same kind, so an approved university no longer shows a greyed Approve button.',
    'Jobs › Priority queue › Course-page search budget: see this month\'s search credits and raise the monthly cap (Platform Admin).',
    'Australian English is also taken from a page whose title is exactly the course title (the CRICOS code is no longer required for English).',
    'Canada: course pages are searched by the title\'s words and accepted when the heading names the same field and the same award; university websites are accepted when the full name is on the home page and the address fits the name.',
    'New Zealand: a university page whose heading is exactly the degree name (optionally with its abbreviation) is accepted for degrees, checked by hand before it was switched on.'
  ],
  bugFixes:[
    'Universities with an approved English policy no longer show other documents waiting with a greyed Approve button.'
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
