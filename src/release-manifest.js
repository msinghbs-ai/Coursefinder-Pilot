// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.67'
export const PACKAGE_VERSION='0.1.489'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'20 Nov 2026',
  title:'4-stage pipeline on Platform Health, Dashboard cards by country, Layer 4 rule groups and ? help',
  changes:[
    'Platform Health shows the 4-stage pipeline under the summary: Official Registers, Page Capture, AI Extraction & Auto-Clean and Live Catalogue, each with its status, what is queued and how many of its checks pass. Select a stage to see what it is doing and open the screen that controls it.',
    'The Dashboard shows five cards with icons (system status, completeness with a bar for Australia, New Zealand and Canada, decisions waiting on you, active blockers and today\'s AI spend against the daily cap) and, for operators, Active failures. A Viewer or Counsellor sees catalogue search only.',
    'Layer 4 Inbox: Waiting, grouped by rule, on the left groups the cards on the page by the check that holds them; Preview the batch lists a group and Show only these narrows the list to it.',
    'A ? on the Dashboard, Platform Health, Layer 4 Review, Courses and Providers headers opens three steps for that screen and a link to the Platform guide.'
  ],
  bugFixes:[
    'Platform Health and the top-bar health dot read stored figures, rebuilt every 5 minutes, instead of counting the work tables on every open; workers that find nothing to do no longer add a log line on every call.'
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
