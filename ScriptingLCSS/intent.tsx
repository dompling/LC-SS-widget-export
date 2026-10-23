// Optional sync step called from Shortcuts > Scripting > Run Script.
// It copies the existing LCWidgetProbe v4 output into Scripting's OWN widget-readable App Group.
// This does not refresh signing, nor does it run/trigger the LC Guest App dylib.
import { FileManager, Intent, Script, Widget } from "scripting"

async function syncSnapshot() {
  const folder = FileManager.bookmarkedPath("LCWidgetExport")
  if (!folder) {
    Script.exit(Intent.text("No LCWidgetExport bookmark. Run the project's index.tsx inside Scripting first."))
    return
  }

  const sourcePath = folder + "/widget_data.json"
  const raw = await FileManager.readAsString(sourcePath)
  const parsed = JSON.parse(raw)

  if (!parsed || !Array.isArray(parsed.activeApps) || !Array.isArray(parsed.allApps) ||
      parsed.lastUpdated === undefined) {
    throw new Error("The source is not a SideStore widget snapshot.")
  }

  // Preserve the original JSON bytes/text, no dates or fields are rewritten.
  const targetDir = FileManager.appGroupDocumentsDirectory + "/LCWidgetData"
  await FileManager.createDirectory(targetDir, true)
  await FileManager.writeAsString(targetDir + "/widget_data.json", raw)
  await Widget.reloadAll()
  Script.exit(Intent.text("Widget data synced from LCWidgetExport."))
}

syncSnapshot().catch(error => {
  console.error("LCSS sync failed:", error)
  Script.exit(Intent.text("Snapshot sync failed: " + String(error)))
})
