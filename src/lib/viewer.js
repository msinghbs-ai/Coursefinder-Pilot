// UI audit Phase 1 (24 Oct 2026): the signed-in person's role rank, readable by any screen without threading a prop.
// The shell (mature-main.jsx) provides it; roles run 1 Viewer … 6 Platform Admin (security.roles, as nav-map.js says).
// Vendor account balances (OpenRouter credit, Firecrawl credits) are shown as figures to the Platform Admin only; everyone
// else sees the state in words.
import{createContext,useContext}from'react'

export const PLATFORM_ADMIN_RANK=6
export const ViewerContext=createContext({rank:0})
export function useViewerRank(){return Number(useContext(ViewerContext)?.rank||0)}
export function useIsPlatformAdmin(){return useViewerRank()>=PLATFORM_ADMIN_RANK}

/** "Within budget" / "Near the limit" / "Used up" for a balance against its floor (or reserve). Near = within 25% above the floor. */
export function balanceWords(remaining,floor=0){
  const r=Number(remaining),f=Number(floor)||0
  if(!Number.isFinite(r))return'Not read yet'
  if(r<=f)return'Used up'
  if(f>0&&r<=f*1.25)return'Near the limit'
  return'Within budget'
}
