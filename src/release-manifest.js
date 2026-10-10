// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.237'
export const PACKAGE_VERSION='0.1.164'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'10 Oct 2026',
  title:'Unpublished providers: background work paused',
  changes:[
    'An unpublished or archived provider no longer has background work picked up: site and page finding, page reads and re-reads, AI matching, course link search, adapter overwrite, provider facts, scholarships, and public and CRICOS contact reads. Work already running finishes, and everything resumes when the provider is published again.',
    'Work a Platform Admin starts by hand (adapter builder, a Firecrawl run, edits) still runs for an unpublished provider, so its record can be fixed before it is published again.',
    'Providers \u203a list: the Published switch says that switching off also pauses the provider\u2019s background work.'
  ],
  bugFixes:[
    'Public contact email: an address on another service (a library help service such as vu.libanswers.com) or a non-enquiry mailbox (library, vet hospital, ethics, philanthropy, partnerships, facilities, research) is no longer taken as the provider\u2019s email. The wrong emails already saved were cleared and those providers are read again.'
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
