// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.1'
export const PACKAGE_VERSION='0.1.423'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'14 Nov 2026',
  title:'Models & services: limits banner, held reasons in words, failed calls in Recent usage',
  changes:[
    'Models & services > AI: a limits banner at the top of the page, above the four panes, says whether limits are enforced. Limits enforced: the daily ceiling and each service\'s cap stop scheduled work when reached. Limits not enforced: they are only reported. It gives today\'s spend and how many services are held, or would be held now, and it stays in view when every pane is closed.',
    'A service that is not running lists its reasons under its state, in words: switched off, no allowed model, no model qualified for it yet, not migrated, or a cap, the ceiling or the credit.',
    'A running service whose last call failed says so on its row, with the kind of failure (cut short, timed out, an error from the AI service, and so on).',
    'Recent usage: the failed calls of the last 24 hours are counted on the card (shown when it is closed too), with their rate and their kinds above the per-call table; a failure count is highlighted, and the list of failed attempts is open.',
    'Since v2.16.0: every AI call goes through its service\'s route with its cascade and caps (worker v0.86.0 to v0.91.0); course page reads are measured in shadow for Lean AI Input, with no change to what is read or sent; the entry requirements v2 trial gained a stored ranked sample and evaluation prompt versions, all held off.'
  ],
  bugFixes:[
    'Services: the five services switched off until a model is qualified for them were listed in a red alert as having "no allowed model". Their cascades name an allowed model; none is qualified yet. They now show Off with that reason, and the red alert is only for services that are switched on and get no model.',
    'A service row said "In use today" with a model when nothing was handed out to the service. It no longer does.',
    'A switched-off row\'s model cell said "No allowed model" when the reason was that no model is qualified for the service. It now says "No qualified model".',
    'On a phone, the note under the Not allowed group of Models ran past the edge of the screen; it now wraps.',
    'Since v2.16.0: the scholarship page picker keeps never-decided pages first, and the entry requirements v2 trial keeps its prompt version\'s settings, after the move to service routes.'
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
