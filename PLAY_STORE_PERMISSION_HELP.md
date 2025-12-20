# Widdle Reader: Play Store "All Files Access" Declaration

Google is very strict about this permission, so you must emphasize that it is **Core Functionality** for an Audiobook Player.

---

### 1. Describe 1 feature in your app that requires a permitted use of the All files access permission.
**Draft Text (to copy/paste):**
Widdle Reader is a specialized audiobook player for DRM-free collections. The core "Library Manager" requires this permission to recursively scan and import user-owned audiobooks. It must access files and metadata in complex directory structures, including folders containing `.nomedia` files which users often utilize to keep audiobooks separate from their standard music library. Without this, the app cannot reliably discover or play the user's personal content.

---

### 2. Usage
**Select:**
- [x] Core functionality

---

### 3. Technical reason (Why not SAF or MediaStore?)
**Draft Text (to copy/paste):**
The Media Store API is insufficient as it ignores directories containing `.nomedia` files, making many audiobook collections invisible to the app. Additionally, the Storage Access Framework (SAF) is unsuitable for large libraries; the performance overhead of SAF for recursive scanning of deep directory structures causes severe latency and app instability. True "All Files Access" is required to provide a performant and reliable experience for users with extensive offline libraries.

---

### 4. Video Instructions
**What your video should show:**
1.  Open the app and go to the "Add Books" or "Add Folder" screen.
2.  Tap the button that triggers the permission request.
3.  Show the system "All Files Access" settings page.
4.  Toggle the switch to grant permission to Widdle Reader.
5.  Go back to the app and show the scanner successfully finding audiobooks in a folder (ideally one that has a `.nomedia` file inside it).
6.  Briefly show one of the found books playing.

**Note:** The video should be a direct screen recording from an Android device or emulator. You can upload it to Google Drive or YouTube (as Unlisted) and provide the link.
