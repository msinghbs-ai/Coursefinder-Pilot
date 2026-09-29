// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.106'
export const PACKAGE_VERSION='0.1.33'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'29 Sep 2026',
  title:'One look across the console; completeness states on Course coverage',
  changes:[
    'Course coverage reports the completeness states for every attribute (present, source says nothing, ambiguous, not yet enriched; stale, rejected, suppressed, not applicable and zero are shown as they start being recorded) and the course completeness score: average completeness, accounted for, fully complete courses, courses by attributes admitted, and the score in the daily trend. Select a count to list those courses with their own completeness.',
    'One set of colours, text sizes, corner radii and shadows for every screen, so the same kind of thing looks the same everywhere. The look is unchanged apart from small alignments.',
    'Shared building blocks: status chips, badges, buttons, metric tiles, empty messages, filter chips and loading rows are now the same component on every screen.',
    'Dates read "29 Sep 2026" and "29 Sep 2026, 2:37 pm"; numbers use Australian grouping; money shows as A$31,680 (US$ for vendor and model costs); percentages show one decimal place.',
    'Layers are always written "Layer 1" to "Layer 4" (no more "L2" or "layer-2").'
  ],
  bugFixes:[
    'Statistics & Rankings cards had unstyled borders and text colours (they used colour names that did not exist).',
    'Dashboard: "Layer 3 cost · 24h" read "unknown" instead of the amount.'
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
