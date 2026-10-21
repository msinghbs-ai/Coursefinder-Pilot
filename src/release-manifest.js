// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.310'
export const PACKAGE_VERSION='0.1.237'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'22 Oct 2026',
  title:'New Zealand enrichment review fixes; daily backup of publishing and settings',
  changes:[
    'Course-page search skips providers whose own website lists too few course pages (one flag on the provider instead of one per course), and universities are matched against their own course list before any title search.',
    'Pages that need a browser are read again within a day in New Zealand; address guesses are no longer made there.',
    'The AI page match is asked only when there are at least two candidate pages, and is retried only while retries find right pages.',
    'Enrich fields asks once more, with a note, when a quote was not on the page, and does not ask again about a page copy that did not state the field.',
    'The daily New Zealand report has a Toolset use sheet: each tool used, worked and did not work, per provider.',
    'Settings › Backup & restore (Platform Admin): a daily copy of each provider\'s Published switch and every setting value; compare, download as a SQL file, or put back.',
    'Layer 2/3 › Flags shows, for each flagged university or course, the tools tried before it was flagged: how often each was used, worked and did not work, with credits and AI cost.'
  ],
  bugFixes:['Two fee pages could not be recorded by the fee reader because of hidden characters in the page; pages with no fee amount are no longer sent to the AI.']
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
