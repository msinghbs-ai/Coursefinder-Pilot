// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.56'
export const PACKAGE_VERSION='0.1.478'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'19 Nov 2026',
  title:'Catalogue › Providers: logos, flags and a tidier table',
  changes:[
    'Catalogue › Providers: each row starts with the provider\'s logo, or a two-letter monogram in a calm colour when no logo is stored yet. The name is in bold with its CRICOS code (or stable key) underneath. Platform Admins can still click the logo to change it.',
    'Five filters stay in the bar (Country, Type, Status, Description, University group). The eight technical ones (State / region, Publication, Adapter, Description quality, Description admission, Description source, Website feed, Zoho feed) are under More filters, whose button shows how many are in use.'
  ],
  bugFixes:[
    'Country codes show a drawn flag for Australia, New Zealand and Canada beside one code pill. On Windows the flag emoji read as "AU AU" or "CA CA".',
    'Extract / refresh description is a small refresh icon beside the name (its tooltip says so), so rows are compact again. Ticking several providers still shows Extract / refresh description now for selected.',
    'The adapter badge (for example Switched off or Testing) reads in full, with Open adapter as an icon beside it. The Type control stays inside its column.',
    'The page tabs under each page title (for example Providers, Campuses, Logos & assets, Archived) are easier to read when not selected.'
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
