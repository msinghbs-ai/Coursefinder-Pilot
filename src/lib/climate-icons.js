// Climate icons for destination.locality_metrics rows with metric_category 'climate' (v2.16.42, Platform Admin 18 Nov 2026 14:23).
// The figures are long-term averages (BOM climate normals), not forecasts, so an icon describes the measure, never the weather today.
// Icons: lucide (ISC licence, already bundled with PIM Admin). The same rule is in the Website API v3 developer guide, so the website can
// draw the same picture with any icon set: the API carries metric_key, numeric_value and unit; the icon is presentation only.
// Rule, first match wins:
//   storm or thunder in the key  -> storm        rainfall or rain in the key -> rain (heavy rain at or above HEAVY_RAIN_MM a year)
//   wind in the key              -> wind         snow in the key            -> snow
//   a mean minimum (°C) at or below SNOW_MIN_C -> snow;  any other mean minimum -> partly cloudy;  a mean maximum or other temperature -> sunny
import{Sun,CloudSun,CloudRain,CloudRainWind,CloudLightning,Snowflake,Wind}from'lucide-react'

export const CLIMATE_ICONS={sunny:[Sun,'Sunny'],partly_cloudy:[CloudSun,'Partly cloudy'],rain:[CloudRain,'Rain'],heavy_rain:[CloudRainWind,'Heavy rain'],storm:[CloudLightning,'Storm'],snow:[Snowflake,'Snow'],wind:[Wind,'Wind']}
// presentation thresholds (the same numbers are printed in the developer guide); not pipeline values
export const HEAVY_RAIN_MM=1500 // fixed: presentation only, documented in the developer guide
export const SNOW_MIN_C=2 // fixed: presentation only, documented in the developer guide

export function climateIcon(key,value){
  const k=String(key||'').toLowerCase(),v=value==null||value===''?null:Number(value)
  if(/storm|thunder/.test(k))return'storm'
  if(/rain/.test(k))return v!=null&&v>=HEAVY_RAIN_MM?'heavy_rain':'rain'
  if(/wind/.test(k))return'wind'
  if(/snow/.test(k))return'snow'
  if(/_min_c$|min_temp|minimum/.test(k))return v!=null&&v<=SNOW_MIN_C?'snow':'partly_cloudy'
  if(/_c$|temp|max/.test(k))return'sunny'
  return null
}
