// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.68'
export const PACKAGE_VERSION='0.1.490'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'20 Nov 2026',
  title:'A cleaner Dashboard, Layer 4 Review by rule with one card at a time, and capture and auto-clean rates',
  changes:[
    'The Dashboard is the role line, the five cards, Active failures and your 3 most recent items under Continue where you left off. Waiting for your approval, Waiting for you, Also and the four summary cards are gone.',
    'Active failures lists genuine failures and warnings only (a job whose last run failed, stuck work, a connection or check failing), worst first, each with the screen that fixes it.',
    'Layer 4 Review opens on Review by rule: every waiting item of a queue grouped by the rule that holds it, with one card at a time on the right. Preview the batch lists the exact records of a rule; only Contains a banned word can be admitted as one confirmed batch, one decision per record. By university, By kind, Grid and Decided are under Other views.',
    'Every held card opens with the amber Main hold reason, banned words are marked in yellow in the proposed text, the cleaned text sits above Remove "word" & Admit, and the action bar is Save Edit & Admit, Approve As-Is and Reject set apart on the right.',
    'Platform Health: Page Capture shows pages captured against the normal rate, and AI Extraction & Auto-Clean shows the auto-clean pass rate against normal, from the stored figures.'
  ],
  bugFixes:[
    'The Dashboard spend card showed "cap not set": it now shows today\'s spend against the US$14.00 daily cap, with its bar.'
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
