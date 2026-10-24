// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.342'
export const PACKAGE_VERSION='0.1.269'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'24 Oct 2026',
  title:'Hotfix: a person\'s course page search runs, a stalled task says why, a held fee takes a page address',
  changes:[
    'Scheduled jobs › Task manager: every running task shows when it last sent work to its tool and when the next attempt is; when nothing has moved for a minute (Tasks: blocked after) it says what is holding it and where to fix it.',
    'Coverage gaps name "web search stopped for this university" instead of counting those courses as queued.',
    'Consumer API unchanged (Decision 266).'
  ],
  bugFixes:[
    'Find course pages started by a person waited for ever at a university whose automatic search had stopped (Otago, 0 of 50); a person\'s task now passes the stop and is sent to the search as soon as it is accepted (Course search: a person\'s task passes the stop). Budgets and the target-only rule still apply.',
    'Layer 4: "Enter another address" on a held fee (identity re-check, fee floor) failed with a technical message; it now binds the page as a person\'s value, reads it again and re-admits the fee. https:// on the university\'s own site only; "Use the new page" no longer shows on a fee item.'
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
