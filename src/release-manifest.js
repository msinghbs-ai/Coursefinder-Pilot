// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.102'
export const PACKAGE_VERSION='0.1.29'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'28 Sep 2026',
  title:'Course attribute badges show where each value really came from',
  changes:[
    'Course attribute badges now come from stored records: CRICOS values show L1, provider-page values L2, tuition checked by the AI shows L3 with the model name, and people\'s decisions L4. Hover a badge to see what resolved it.',
    'Where a university has no provider tuition but CRICOS registered tuition exists, the course shows "CRICOS tuition applies" instead of "Awaiting L2".',
    'Attributes that no Layer 2 source collects for that university show "Not collected" instead of waiting.',
    'Provider course pages are refreshed every 90 days instead of weekly (Decision 162); tuition is read once per fee year.',
    'Layer 2 course extraction works again: discovered course pages are kept when a profile\'s settings change (it had stopped on 26 Sep). RMIT\'s course refresh is switched back on (Decision 161).'
  ],
  bugFixes:[
    'Tuition admitted by the Layer 3 AI (242 courses) was badged as Layer 2.',
    '"Awaiting L3" was shown for course URL, description, intakes and English, which Layer 3 never handles.',
    'Delivery mode showed "Awaiting L2" although CRICOS course locations give it.',
    'The course page looked up Layer 2 results by course code alone instead of within the course\'s own provider.'
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
