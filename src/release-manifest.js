// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.232'
export const PACKAGE_VERSION='0.1.159'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'10 Oct 2026',
  title:'Adapter builder says what happens; course finder address entered by hand stays',
  changes:[
    'Adapter builder \u203a Find course pages: with no website on record it asks for the provider\u2019s own website and starts looking for course pages on it. With a website, \u201cFind course pages now\u201d starts page finding for this provider only and says how many courses it is looking for.',
    'Adapter builder \u203a Capture sample pages: a course page can be entered by hand. Pick the course and paste its page on the provider\u2019s own website; it becomes the course\u2019s official page (entered by hand) and is captured as a sample.',
    'Adapter builder: no step asks for a reason any more. A standard line is kept in the log. Steps that use Firecrawl credits or the AI allowance still ask a plain yes/no.'
  ],
  bugFixes:[
    'Provider \u203a Course finder address: a value changed by hand now shows \u201cEntered by hand\u201d and automation no longer replaces it. \u201cLet automation update this\u201d hands it back.',
    'Adapter builder: \u201cAdd to Firecrawl targets\u201d appeared to do nothing. It only saved a setting, and a provider with no website was skipped silently. Replaced by the steps above.'
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
