// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.239'
export const PACKAGE_VERSION='0.1.166'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'11 Oct 2026',
  title:'Scholarships: published only, course links, editions and automatic publishing',
  changes:[
    'Wix, the website and Zoho receive published scholarships only, whatever the caller asks for.',
    'A scholarship page that names no study level, field or course links to all of the provider\u2019s courses open to international students, marked as such; a faculty the reader cannot match no longer stops the links.',
    'One scholarship, one record: semester or year editions and register copies are held as \u201canother edition\u201d, and the provider\u2019s own current record is the one listed.',
    'Scholarships that pass every check are published automatically every hour as a batch named \u201cauto-publish\u201d, for review (setting auto_publish).'
  ],
  bugFixes:[
    'The website scholarship APIs returned every active record, published or not, unless the caller asked for published only; the Zoho lookup and search also returned unpublished and inactive ones.',
    'A percentage that is an academic result (\u201cCWA of 95%\u201d) made the award value ambiguous (Curtin\u2019s John Curtin Global Excellence Scholarship, 40% off tuition).',
    'The value text shown with a scholarship started mid-word.'
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
