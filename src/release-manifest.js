// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.19'
export const PACKAGE_VERSION='0.1.441'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'17 Nov 2026',
  title:'Destination data page; campus localities in Layer 4; locality on API v3 providers',
  changes:[
    'New page Catalogue › Destination data (Curator and above), with five tabs: Overview & editions, Localities & postcodes, City metrics & costs, Study rules, Careers & outcomes. Approval, publication and withdrawal are the Platform Admin\'s and always ask for a reason. The tables are empty until the first loads.',
    'Layer 4 Review › Inbox: new kind Campus locality. A campus whose postcode is below the match share waits there; one decision settles the postcode for every campus in it.',
    'Course detail › Recognition card: the schemes a course is registered under, the field-of-study scheme of its country, and the study rules proven for it. Provider detail: the primary campus, the locality each campus maps to, and provider registrations by scheme, with PGWP shown apart from the DLI number.',
    'Platform health › Data delivery: Destination loads lists the destination load jobs with Run now, and what waits for a person.',
    'API v3 provider (website and Zoho): each campus gains locality, null until its postcode has an approved match. The v2 APIs are unchanged.'
  ],
  bugFixes:[
    'Administration › Users & roles: sending a password reset email is now recorded in the access history.'
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
