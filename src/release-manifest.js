// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.66'
export const PACKAGE_VERSION='0.1.488'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'20 Nov 2026',
  title:'Clearer description review, automatic removal of banned words and a Platform Health summary',
  changes:[
    'Description cards show the main hold reason in plain English at the top, with one-click Remove "word" & Admit when a banned word is the only problem.',
    'Each description card has one action bar: Remove "word" & Admit, Save Edit & Admit, Approve As-Is and, set apart, Reject. The duplicate buttons underneath are gone.',
    'University descriptions held only for a promotional word on the readers\' list are admitted automatically with the word removed, after the same checks; the word list is also given to the reader up front.',
    'Human Edits lists the words reviewers remove most often, marked as already on the list or a candidate to add.',
    'Platform Health opens on a plain-English summary (health, AI spend against the daily cap, blockers, Layer 4 waiting) and Needs attention (failed jobs, stuck work, connections down); everything technical is under Technical details.'
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
