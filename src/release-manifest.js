// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.42'
export const PACKAGE_VERSION='0.1.464'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'18 Nov 2026',
  title:'Coverage now, climate icons and how the data connects',
  changes:[
    'Coverage & completeness › Courses starts with Coverage now: readiness by country (AU, NZ, CA, UK, IE, US by Courses, Providers & campuses, AER & grade scales, Scholarships, Destination editions) and every recorded field with its share. No field list is fixed in the screen: a newly recorded field appears by itself, marked Not labelled until it has a label.',
    'Targets, the 7-day change, trend lines and Courses by fields admitted (0 of N to N of N) appear when the coverage read is live; its database change is with S2-Build. Until then the screen says so.',
    'The portals that supply course links and the Stalled fields counters are retired from Coverage; Enrich fields keeps its stalled-field controls.',
    'Destination data › City metrics & costs: each climate figure shows an icon (sunny, partly cloudy, rain, heavy rain, storm, snow, wind) chosen by one rule. The figures are long-term averages, not forecasts; the developer guide gives the website the same rule.',
    'Guides › Platform guide › How the data connects: how destinations, providers and their campuses, courses (study load, empty reason, entry requirements, scholarships), study rules and career outcomes join, with the API v3 paths the website and Zoho read.'
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
