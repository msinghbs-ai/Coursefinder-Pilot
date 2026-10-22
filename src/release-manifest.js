// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.323'
export const PACKAGE_VERSION='0.1.250'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'23 Oct 2026',
  title:'Course page fees through the AI fee reader; fee proofs for New Zealand',
  changes:[
    'Settings › Identify the page: every proof the admission gate reads can now be ticked, including Page bound by a person, University page and the adapter proofs. Before, changing English, intakes or the official address for a country that held one of these proofs was refused.',
    'Course pages: the University of Auckland catalogue\'s newer-version link is followed even when it sits inside escaped markup, so the 2027 page and its fees are read.',
    'Read with AI now runs the AI fill even for fields where AI earlier found no value (the hold is released with the reason given), and sends the page\'s fee to the AI fee check again. A page fee that changed after an earlier AI fee check is checked again.',
    'Fee reader (AI): a course\'s own page that shows an international fee, for a course with no fee held, is now read by the AI fee reader with the same checks as fee schedules; passes are admitted and the rest go to Layer 4. Since Layer 3 was retired these fees had no way in outside universities with an adapter. Settings: Fee reader: read course pages, course pages queued a run.',
    'New Zealand international fees are now also admitted from course pages proved by exact title, title with level, or bound by a person (Platform Admin decision, 23 Oct 2026). The fee still passes the AI fee check before it is admitted.'
  ],
  bugFixes:['Settings › Identify the page refused every change to English, intakes and official address for AU, NZ and CA (unknown identity).']
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
