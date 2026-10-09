// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.225'
export const PACKAGE_VERSION='0.1.152'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'9 Oct 2026',
  title:'Lists fill the page; course and provider panels as cards',
  changes:[
    'Every list fills the width of the page, and each column can be resized by dragging the edge of its heading (double-click to reset). Widths are remembered in this browser.',
    'Course and provider panels open on coloured pills (level, field, delivery, CRICOS code, publication) and cards with the main facts \u2014 tuition used, registered cost, intakes, English, campuses, courses, scholarships, contacts \u2014 that reflow from one to four columns with the width.',
    'Values you can change are shown as cards with a short Automated or Entered by hand pill. Evidence, regulatory, operational and raw identifier lists are no longer listed in the panels; evidence still opens from the panel header, and related insights sit in a closed \u201cMore\u201d section.',
    'Campus and other record panels use the same pills and cards.'
  ],
  bugFixes:['Scholarships list: one scholarship with a long list of nationalities stretched the \u201cWho it is for\u201d column and pushed Value, Courses and Closes off screen. Long lists now show the first two and a count.']
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
