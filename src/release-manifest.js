// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.85'
export const PACKAGE_VERSION='0.1.12'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'24 Sep 2026',
  title:'Layer 4 batches',
  changes:[
    'Layer 4 has a Batches view (switch between "Review one by one" and "Batches"). Repeat cases are grouped by task and suggestion, for example tuition fees where the page shows a course total.',
    'Preview a batch before deciding: see every item with its page quote, untick any you are unsure about, give one reason, and type a confirmation such as "REJECT 41".',
    'Every item in a batch is recorded exactly as if decided on its own, and the batch itself is recorded too. If any item cannot be decided, none are.',
    'Applying a batch needs the Pipeline Operator role; curators can preview.',
    'Scholarship scope items now show the scholarship and provider names, and scholarship scope batches and history sit in the Batches view.'
  ],
  bugFixes:[
    'Approve is no longer offered for scholarship scope items, where it could not be applied.',
    'Scholarship cohort reasons are shown in plain English instead of internal codes.',
    'The batch panel no longer inserts itself into the page; Layer 4 shows it deliberately in the Batches view.'
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
