// Scripting widget: display the SideStore snapshot and run an iOS 27+ configured Shortcut.
// Refresh button and data sync are independent.
// Requires Scripting build that supports shortcutIndex (3.2.2+ TestFlight docs).
import { Button, FileManager, HStack, Text, VStack, Widget } from "scripting"

type AppItem = {
  name: string
  bundleIdentifier: string
  refreshedDate: number | string
  expirationDate: number | string
}

type Snapshot = {
  activeApps: AppItem[]
  allApps: AppItem[]
  lastUpdated: number | string
}

// Scripting widgets can read their own App Group, not another app's private App Group.
const cachedPath = FileManager.appGroupDocumentsDirectory + "/LCWidgetData/widget_data.json"

function parseJSONEncoderDate(value: number | string | undefined): Date | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    // SideStore uses Swift JSONEncoder default: seconds since 2001-01-01T00:00:00Z.
    return new Date(Date.UTC(2001, 0, 1) + value * 1000)
  }
  if (typeof value === "string") {
    const result = new Date(value)
    return Number.isFinite(result.getTime()) ? result : null
  }
  return null
}

function calendarDaysUntil(date: Date): number {
  const today = new Date()
  return Math.round((
    Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) -
    Date.UTC(today.getFullYear(), today.getMonth(), today.getDate())
  ) / 86400000)
}

let snapshot: Snapshot | null = null
try {
  const raw = FileManager.readAsStringSync(cachedPath)
  const parsed = JSON.parse(raw)
  if (Array.isArray(parsed.activeApps) && Array.isArray(parsed.allApps)) {
    snapshot = parsed as Snapshot
  }
} catch (error) {
  console.log("LCSS widget: no Scripting-side snapshot yet", error)
}

// Only LiveContainer is expected. Never invent LC2/LC3 records.
const app = snapshot?.activeApps.find(a => a.bundleIdentifier === "com.kdt.livecontainer") ??
  snapshot?.allApps.find(a => a.bundleIdentifier === "com.kdt.livecontainer")
const expiration = parseJSONEncoderDate(app?.expirationDate)
const updatedAt = parseJSONEncoderDate(snapshot?.lastUpdated)
const daysRemaining = expiration ? calendarDaysUntil(expiration) : null
const isStale = !updatedAt || Date.now() - updatedAt.getTime() > 24 * 3600 * 1000

Widget.present(
  <VStack spacing={10}>
    <Text>LiveContainer</Text>
    <HStack spacing={8}>
      <Text>{daysRemaining == null ? "暂无签名数据" : daysRemaining < 0 ? "已过期" : "剩余 " + daysRemaining + " 天"}</Text>
    </HStack>
    <Text>{snapshot ? (isStale ? "缓存可能已过期" : "来自 SideStore 快照") : "请先运行数据同步脚本"}</Text>
    {/* shortcutIndex 0 is configured manually in Edit Widget > Shortcuts. */}
    <Button title="刷新签名" systemImage="arrow.clockwise" shortcutIndex={0} />
  </VStack>
)
