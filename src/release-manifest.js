// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.131'
export const PACKAGE_VERSION='0.1.58'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'1 Oct 2026',
  title:'Melbourne time, plainer screens',
  changes:[
    'All times are shown in Melbourne time (with daylight saving) for every viewer; Automations no longer shows India time, and weekly or monthly schedules name the Melbourne day.',
    'Plain wording replaces internal terms (governed, canonical, bounded, milestone and change-control codes) on Evidence, Rankings, Providers, Layer 1, Scheduled jobs, Platform maturity and Users. Known job errors read in plain words.',
    'Counts say what they cover: Dashboard and lists count every status; Coverage counts active Australian courses.',
    'Rankings › Datasets is a proper list: show or hide each dataset, add one, and go to its imports.',
    'Providers › Onboarding now holds the provider onboarding queue (moved from Layer 2), with the older onboarding cases collapsed beneath it.',
    'Users & roles explains what each role can do; the leftover Admin button is gone.',
    'Scholarship publishing reasons and Platform health issues link to where they are fixed.'
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
