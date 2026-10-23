// Run once in the Scripting app to grant access to LC's exported folder.
// The v4 LCWidgetProbe dylib writes into LiveContainer/Documents/LCWidgetExport.
import { DocumentPicker, FileManager, Widget } from "scripting"

async function setup() {
  const existing = FileManager.bookmarkedPath("LCWidgetExport")
  if (!existing) {
    const result = await DocumentPicker.pickDirectoryBookmark({
      preferredName: "LCWidgetExport",
    })
    if (!result) {
      console.log("Cancelled folder authorization")
      return
    }
    if (result.bookmarkName !== "LCWidgetExport") {
      console.log("Bookmark was renamed to:", result.bookmarkName)
      console.log("Update the bookmark name in intent.tsx or re-create it as LCWidgetExport.")
      return
    }
  }

  console.log("Authorized folder: ", FileManager.bookmarkedPath("LCWidgetExport"))
  console.log("Now run the Scripting 'Run Script' action to copy the current snapshot.")
  // Do not assume permission implies Widget Extension can read LC's own sandbox.
  // Instead, intent.tsx explicitly syncs into Scripting's App Group directory.
  await Widget.reloadAll()
}

setup().catch(error => console.error("Setup error:", error))
