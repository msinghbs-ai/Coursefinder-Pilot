// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.233'
export const PACKAGE_VERSION='0.1.160'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'10 Oct 2026',
  title:'Only the provider\u2019s own website or the regulator',
  changes:[
    'A provider\u2019s website, course finder address and course pages come only from its own website, the regulator, or a value entered by hand. Course directories (such as ACIR, HigherStudy, OneUEdu, Study Melbourne course search and Find the Courses) are on the third-party list in Reference data and are never used. Hotcourses stays for logos only.',
    'Provider panel: the Website and Course finder address show whose they are: provider\u2019s own site, regulator, third-party (not used), or not confirmed.',
    'Course finder addresses that pointed at a course directory are cleared and the website search looks for the provider\u2019s own site again. It now accepts a site only when the CRICOS code is on its home page, or on a deeper page of an address that fits the provider\u2019s name.',
    'Intakes, English requirements and official course links read from course directories are withdrawn (values entered by hand are kept). Those courses look for their page on the provider\u2019s own site again.',
    'Where the search had already found the provider\u2019s own site and no website was recorded, it becomes the provider\u2019s website.'
  ],
  bugFixes:[
    'Provider website not found (for example Britts College): the search had accepted a course directory page because it showed the CRICOS code, and sites it found were never copied to the Website.'
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
