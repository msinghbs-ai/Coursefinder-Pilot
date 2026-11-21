// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.79'
export const PACKAGE_VERSION='0.1.501'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'21 Nov 2026',
  title:'India team feedback: clearer filters, durations in years, full statistics names',
  changes:[
    'Courses, Providers, Scholarships and Entry requirements: the destination filter reads Study destination; on Entry requirements the source filter reads Student\'s education country.',
    'Course detail and the Course catalogue: durations read in years, with the stored weeks or months in brackets (3 years (156 weeks)).',
    'Provider contacts: a line says what the page is for, and an × clears the chosen provider.',
    'Courses › Empty reason and Providers › On website and In Zoho CRM (were Website feed and Zoho feed): each filter shows a note on what it means.',
    'Rankings & statistics: QILT and PRISMS cards carry their full names, and each card says who publishes it.'
  ],
  bugFixes:[
    'Entry requirements: a counsellor who chose a provider saw the data team\'s Read now panel. It now shows from Curator up only.',
    'Provider contacts: once a provider was chosen it could not be cleared.'
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
