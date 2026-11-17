// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.29'
export const PACKAGE_VERSION='0.1.451'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'17 Nov 2026',
  title:'Courses: Study load and Empty reason; Campuses: Primary and Locality',
  changes:[
    'Catalogue › Courses: two new columns in the Columns picker, Study load (full-time, part-time, or both) and Empty reason (why a course\'s empty values are empty on purpose, shown as a badge). Both are off until you show them.',
    'Catalogue › Courses: two new filters under Filters, Study load (including Not held) and Empty reason (any reason, one reason, or No reason recorded, which finds courses whose gaps are still to fill).',
    'Catalogue › Providers › Campuses: new Primary column (badge) and Locality column. The locality is looked up from the campus postcode and says when it is still a draft in Destination data.',
    'Campuses: new Primary filter and a Locality search box in the filter bar (type a name, press Enter).',
    'The Campuses list now counts courses only for the rows on the page, so it opens faster.'
  ],
  bugFixes:[
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
