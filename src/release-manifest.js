// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.180'
export const PACKAGE_VERSION='0.1.107'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'3 Oct 2026',
  title:'Firecrawl work: target universities, use cases and a report for Firecrawl support',
  changes:[
    'Firecrawl is used by use case: Read pages (course-like pages that need a browser or refused a plain read) and Find pages (a search on the university’s own site for courses without a page). Each run is started with a reason and stops at its own credit allowance.',
    'Target universities: a rule of settings (countries, name pattern, exclusions, least active courses per country, international-student registers) plus additions or removals by hand. Firecrawl is used only for targets (a setting).',
    'Every Firecrawl call a run makes is logged with the scrape id, HTTP status, page status, error, credits and proxy used. The report for Firecrawl support can be copied or downloaded.',
    'The platform’s Firecrawl allowance now follows the balance Firecrawl reports (Growth plan, 500,000 credits).'
  ],
  bugFixes:[
    'The monthly Firecrawl limit was still the old 100,000-credit plan, so the platform was about to stop its own Firecrawl work at 86,000 credits used while Firecrawl reported 490,000 left.'
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
