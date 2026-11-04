// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.480'
export const PACKAGE_VERSION='0.1.407'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'5 Nov 2026',
  title:'Intake dates from every valid academic calendar, with process results',
  changes:[
    'Layer 2/3 Operations has a Process results panel: for each of the top Australian universities, the saved measurement of the intake dates process: courses and stored course pages, valid and set-aside calendars, calendar year and freshness, intake values held and in the Website API source, what was missed and why with its next action, when it is looked at again, and the calendars, reader findings and recent decisions with their quotes and documents. Operators can measure on request.',
    'Intake dates now use every main teaching calendar a university has, not only the latest one. Calendars for another campus, a residential college, exchange or a pathway provider are set aside with the reason and routed to a person.',
    'A course page that gives only a month ("February intake") takes the calendar\'s date when exactly one teaching start falls in that month and year (Platform Admin decision 5 Nov 2026). Orientation, enrolment and deadlines never count as a start; an ambiguous month keeps its month.',
    'Academic calendars are read again from their stored copies with dated starts, application deadlines (international first) and the calendar\'s scope; what the reader cannot prove becomes a finding given to its next read. No Firecrawl.'
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
