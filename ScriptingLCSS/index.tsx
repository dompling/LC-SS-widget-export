// First-run manual import from Files into Scripting's App Group.
// The documented DocumentPicker API is pickDirectory(), not pickDirectoryBookmark().
// This script does not establish a persistent bookmark automatically.
import { DocumentPicker, FileManager, Widget } from "scripting"

async function setup() {
  const folder = await DocumentPicker.pickDirectory()
  if (!folder) {
    console.log("Folder selection cancelled")
    return
  }
  const source = folder + "/widget_data.json"
  const raw = await FileManager.readAsString(source)
  const parsed = JSON.parse(raw)
  if (!Array.isArray(parsed.activeApps) || !Array.isArray(parsed.allApps)) {
    throw new Error("Selected folder does not contain an official SideStore widget snapshot")
  }
  const output = FileManager.appGroupDocumentsDirectory + "/LCWidgetData"
  await FileManager.createDirectory(output, true)
  await FileManager.writeAsString(output + "/widget_data.json", raw)
  DocumentPicker.stopAcessingSecurityScopedResources()
  console.log("Original widget snapshot imported into Scripting App Group")
  await Widget.reloadAll()
}

setup().catch(error => console.error("LCWidgetImport error:", error))
