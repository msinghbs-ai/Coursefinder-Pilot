// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.61'
export const PACKAGE_VERSION='0.1.483'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'20 Nov 2026',
  title:"Completeness bars, Missing field pills, provider bulk bar and provenance panel; security headers and CI gates",
  changes:[
    "Catalogue \u203a Courses and Providers: a Completeness bar on every row. Courses draw the existing six-signal score (registration, structure, fee, intake, English, description); Providers show the share of nine tracked fields held. The bar is a progress bar with the percentage as its label, with no colour bands.",
    "Catalogue \u203a Courses and Providers: a Missing field pill bar. Courses: Fee, Intake, English, Scholarship, Description and Study load narrow the list on the server through filters the list already had. Providers: the nine tracked fields (description, website, city, state or region, type, phone, email, address, established year); several pills keep providers that lack every field chosen, and Export CSV, total and rows agree.",
    "Catalogue \u203a Providers: tick providers to get a bulk bar with Fill fields (description only), Export selected (CSV, with each provider's completeness and missing fields) and Clear.",
    "Catalogue \u203a Providers detail drawer: a Completeness and provenance panel showing the nine fields as Held or Missing and the description's source as Register, AI verified or Human input \u00b7 Locked. Other fields do not record their source per field yet, and the panel says so.",
    "Guides: the Counsellor, Curator and Platform Admin role guides (version 1.1) and the Courses and Providers page guides describe completeness, Missing field pills, the bulk bar and provenance, Intake Run & Validate and Layer 1 country preparation.",
    "Security: the Cloudflare Worker now sends a Content-Security-Policy, Strict-Transport-Security, X-Frame-Options DENY, X-Content-Type-Options nosniff, Referrer-Policy and Permissions-Policy. Page text read from a site is fenced as untrusted, with hidden markup removed, before any model sees it. Website API v3 no longer forwards any database message to the caller. Pull requests run a secret scan, a dependency audit and a CycloneDX SBOM."
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
