// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.481'
export const PACKAGE_VERSION='0.1.408'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'5 Nov 2026',
  title:'Intake recovery: the calendar year from its own section, durable failure reasons and publication checks',
  changes:[
    'The calendar reader now takes a start\'s year from the section it sits in: the heading above it, the document title, or the year tabs a page shows above repeated term blocks (as UNSW\'s academic calendar does). A year from a neighbouring section or a note about future changes is rejected, and a start with no provable year is never given one.',
    'Stored calendars are read again when the reader changes, but only the main teaching calendars of the top Australian universities whose intake rows still miss a date; other calendars are set aside as not needed until they are.',
    'Every intake row that is not completed carries a durable reason (for example stale calendar edition, academic year unproven, course identity unresolved, admission held) with what will bring it back. A deterministic failure is not looked at again until its inputs change.',
    'Every admitted intake value is checked against the Website API v2 source; a value admitted but not published is shown as a failure until the source carries it.',
    'A calendar whose stored copy is an old edition can be read again by the existing source reads, within at most 40 Firecrawl credits in total for the top 10 universities, with the credits and the useful yield recorded.',
    'Process results shows the intake recovery: values admitted and published by university, source, year and precision; skipped and failed rows by reason with the next look; refresh credits and yield; the reader and the jobs.'
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
