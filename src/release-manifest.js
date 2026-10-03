// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.166'
export const PACKAGE_VERSION='0.1.93'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'3 Oct 2026',
  title:'One Academic calendars list; parser reads Curtin-style calendars',
  changes:[
    'Layer 4 › Attributes › Academic calendars: the Start months by hand panel is folded into the list. A university whose calendar page gave no months is a row of the same shape — Intake 1, Intake 2, the periods its course pages name, the number of intake reviews waiting — with the calendar page address to fill in; Save months writes the months by hand and the waiting intake reviews are answered within 10 minutes.',
    'Calendar parser v0.2.2 (worker v0.13.5): a period named on its own section row or heading (Semester 1, then Start date | Monday 16 February) is read, as on Curtin\'s calendar. All 392 stored calendar pages were re-parsed: 68 carry a proposal; Curtin now suggests February and July.',
    'Provider drawer (Providers › open a provider): values are edited inline, no fold — name, website, city, course finder address, applicants and description first, then the provider\'s facts in priority order (university group, ID, stable key, country, course and scholarship counts, status), then contact details, then the contact card, then world rankings and context.',
    'Scholarships list: an Audience filter (International students / Domestic / All) and the Award column clipped to one line so the table no longer runs past the page. Finding: every scholarship on record is marked for international students today, so the filter separates nothing until the audience is read from each scholarship\'s wording — a separate step.',
    'Course drawer: the editable tuition field is named "Tuition from the course page (international)"; for an Australian course with none it says the tuition shown to counsellors is the registered CRICOS course cost below (Decision 242), so the two are not the same field.'
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
