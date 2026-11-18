// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.44'
export const PACKAGE_VERSION='0.1.466'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'18 Nov 2026',
  title:'Course descriptions: 1 to 2 sentences, plain-English holds and four decisions',
  changes:[
    'Layer 4 Review › Inbox, Course description cards: a Why this is held box says, in plain words, why the description waits and what to do, with how firmly the page matched the course, whether every quote is on the page and the sentence count against the limit.',
    'Course description cards have four decisions: Approve as read, Re-read (1-2 sentences) (the stored page is read again; the course is not marked bad), Approve all verified for provider (type the count shown to confirm) and Reject (bad page / wrong course). University description cards keep Approve as read and Reject.',
    'Course descriptions are written in 1 to 2 sentences (about 180 to 360 characters) about the course\'s focus, core skills and stated career outcomes, without intake dates, campus addresses, fees or duration. A description read from the course\'s own page (its CRICOS or NZQA code, or its exact title) is admitted by the machine rule without waiting for a person.'
  ],
  bugFixes:[
    'A course description card no longer says it is one of the university\'s first descriptions when that was not why it waited.'
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
