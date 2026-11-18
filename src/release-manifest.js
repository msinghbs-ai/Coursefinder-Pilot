// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.44'
export const PACKAGE_VERSION='0.1.466'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'18 Nov 2026',
  title:'Around this course and provider; metric type pills; Preview as',
  changes:[
    'Course detail: a new read-only "Around this course" block. Location & weather shows each campus city with its summer and winter means, annual rainfall and climate icon (BOM) and the city population (ABS), with the attribution beside them. Career pathway shows occupations, growth, median salary and shortage status (JSA), or says plainly that the figures are still loading. Visa & living-cost snapshot shows the work limit, post-study work rights, the financial-capacity benchmark, visa charges and health cover (Home Affairs). Entry requirements & scholarships shows the first entry rows and published scholarships.',
    'Provider detail: a new read-only "Around this provider" block with Rankings (QS, THE and ARWU latest and previous editions, and any subject ranks), Campus city profiles (weather and population for each campus city) and Scholarships & accreditations.',
    'Destination data › City metrics & costs: Metric type pills (All, Climate & Weather (BOM), Population & Demographics (ABS), Careers, Jobs & Salaries (JSA), Study Rules & Living Costs (Home Affairs)). Careers and Study rules open their own lists in place, with living-cost city figures beside the rules.',
    'Viewers and Counsellors see student-facing values only in the Course and Provider detail: automated and entered-by-hand tags, rule ids, match shares, edition and approval status, Layer 4 state, AI read details and raw quotes are hidden. Editors and Platform Admins keep them, and can use "Preview as: Admin | Counsellor | Viewer" in the detail header to see a lower role\'s view.'
  ],
  bugFixes:[]
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
