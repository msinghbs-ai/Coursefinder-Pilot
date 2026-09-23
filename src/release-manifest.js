// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.80'
export const PACKAGE_VERSION='0.1.7'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'23 Sep 2026',
  title:'Automated tuition admission & navigation clean-up',
  changes:[
    'Layer 3 now validates Layer 2 tuition fees automatically on a schedule: confirmed fees are recorded in the catalogue and appear in search and the website API.',
    'Administration > Environment migration adds Activate and Pause for Layer 3 AI profiles, with its own required reason; every activation, refusal and pause is kept in an audit trail.',
    'Layer 3 - AI Interpretation shows live queue status by task.',
    'An OpenRouter API Key button is available to Platform Admins from any screen.',
    'Layer 4 review items now explain in plain English what happened and what to check, including the fee amount.',
    'Fees held back at admission (for example, a conflict with an existing fee) now appear in Layer 4 for a person to decide.',
    'Navigation: Completeness, Statistics & Rankings and Compare are grouped under Quality & Insights. Review Queue is retired; old links open Layer 4.',
    'The website API adds course search and scholarship search.'
  ],
  bugFixes:[
    'The Dashboard Open reviews tile and review message now open Layer 4 instead of an empty, retired queue.',
    'Activating an AI profile no longer records the pre-filled "Production credential rotation" text as its reason.',
    'The OpenRouter card in Environment migration no longer overlaps the card beside it.',
    'One failed item no longer stops a whole Layer 3 batch.',
    'Tuition checks no longer treat a course total, or a fee marked only "indicative", as an annual fee.',
    'A fee year is only accepted when the page shows it next to the amount.'
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
