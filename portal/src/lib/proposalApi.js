import { rpc } from './api.js'

// Student proposals. Every call is a public.portal_proposal_*_v1(p_args jsonb) function (the Release 2 contract in the portal
// design document). The database decides who may call it (Counsellor and above) and builds each course snapshot. Until the
// functions are live a call answers "missing" and the screens say so; nothing here crashes.
const call = (name, args) => rpc(name, { p_args: args })

export const listProposals = args => call('portal_proposal_list_v1', args)
export const getProposal = args => call('portal_proposal_get_v1', args)
export const saveProposal = args => call('portal_proposal_save_v1', args)
export const refreshProposal = args => call('portal_proposal_refresh_v1', args)
