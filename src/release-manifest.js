// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.213'
export const PACKAGE_VERSION='0.1.140'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'7 Oct 2026',
  title:'Operator screens cleaned up',
  changes:[
    'Raw settings text (JSON) is now under a closed Advanced (Platform Admin) section, shown only to a Platform Admin: on Scrapers & fetchers (request template, capabilities and billing), in each university\u2019s adapter settings, and in the Layer 4 review drawer\u2019s technical detail.',
    'Layer 2 \u203a Adapters shows the university list first. The fee dry run and the fee range and award link settings are now below the list.',
    'Firecrawl credits left are shown once, on Models & services. Layer 2 \u203a Adapters links there instead, and still shows the stop warning when the reserve is reached.',
    'Two old ranking scripts that were no longer loaded have been removed from the code.'
  ],
  bugFixes:['Links and notes that pointed to Environment & integrations now say Settings, the page\u2019s current name.']
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
