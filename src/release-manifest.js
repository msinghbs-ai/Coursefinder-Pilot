// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.76'
export const PACKAGE_VERSION='0.1.498'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'21 Nov 2026',
  title:'Layer 4 Review: three decisions, clear filters and a fuller guide',
  changes:[
    'Layer 4 Review: one filter row (Module / Field, University, Destination country, Source country, Decision bucket) replaces the row of queue buttons and the view row; the other views and the AER order are under Advanced filters (N).',
    'Each Layer 4 card shows the entity, the proposed value beside the live one, the official source, why it is held with a hint, and three decisions: Yes (Approve), No (Reject) and Resubmit to Review with AI. The queue\'s other choices are under More options; the reference and timings are under Technical detail.',
    'No (Reject) offers one-click reasons: Wrong course, Outdated year, Bad parse, Not offered. Resubmit shows today\'s AI budget before you confirm (entry requirements are re-read from the stored copy at no cost).',
    'Descriptions are two entries of Module / Field: Course description and University description, each with its own count.',
    'Course detail: an empty Tuition, Intakes, English or course page shows why: In Layer 4 review, University-wide rule applies, No official website / course URL on file (Curators add the official address there), or Not stated on institution page.',
    'Help › Platform guide: Filters & badges (every filter on Layer 4, Courses, Providers, Entry requirements, English and Scholarships), a Layer 4 guide, four worked examples and What StudySearch covers.'
  ],
  bugFixes:[
    'Layer 4: Approve all verified for provider showed the queue\'s count while the check counts the provider\'s own verified descriptions, so it was refused. It now shows and fills the provider\'s count.',
    'Layer 4: the queue labelled University description also held course descriptions; Course description and University description are now separate.',
    'Layer 4: after a decision the queue count, All in this queue and Card X of Y could differ by one or two; all three now come from one fresh read.',
    'Course descriptions read from a page that the course\'s own CRICOS or NZQA code proves are no longer held as Page match not clear enough.'
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
