// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.492'
export const PACKAGE_VERSION='0.1.419'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'6 Nov 2026',
  title:'Course descriptions: source-backed review and accurate publication',
  changes:[
    'Enrich fields shows course descriptions ready for review, stale proposals and held readings, with source checks, held reasons, claim-word examples and the stratified trust-policy sample.',
    'Layer 4 opens the ready descriptions or sample in the existing Inbox, with sentence and character checks, source evidence and quick reasons. Every admission still needs an individual human decision.',
    'Proposed, admitted by a person and published to the website stay separate. Publication requires the matching published search document and the existing provider, course and Layer 4 visibility rules.',
    'One AI re-ask for a length or sentence-count breach ships off. After verification it can be enabled by a recorded setting change within existing spending limits; the same source and pinned model are used and every rule is checked again.'
  ],
  bugFixes:[
    'Previous and the item range remain available on the final reviewer page.',
    'The re-ask setting permits only zero or one, and unsupported values fail closed without another AI call.',
    'Course descriptions have separate claim and marketing word settings, initially identical to the provider lists; the limits and human admission policy are unchanged.'
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
