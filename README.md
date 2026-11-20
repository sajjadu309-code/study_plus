# StudyPulse Mobile Pro — Flutter source package

This is a fresh, **source-only Flutter project** built for your Flutter 3.47.x / Dart 3.13.x setup. It uses the **same Supabase project and the same `sp2_items` table** as your StudyPulse Mobile Rebuild. It does not modify older `tasks` or `daily_study_tasks` tables.

This package has not been compiled by the authoring environment. **You must run `flutter analyze`, `flutter test`, and a real Android build** before relying on it. The `setup_windows.ps1` script stops if these checks fail. Google Drive requires your own Google Cloud OAuth credentials.

## Main features

- Modern Material 3 UI, 5 accent colors and dark mode.
- Student name, roll number, program/semester, photo on dashboard.
- Supabase email/password login and sign-up.
- Book/topic CRUD, assignments, quizzes, exams, tasks, habits, expenses, focus timer, dashboards.
- Upload private PDF, DOCX, PPTX, TXT, MD, JPG, PNG files (15 MB maximum per file).
- PDF page viewer; images with pinch-zoom; DOCX/PPTX readable text viewer.
- Heading-based topics suggested from a document and reviewed before saving.
- Generate balanced exam revision sessions from unfinished topics of a chosen book, exam date, session minutes and daily capacity.
- Preview schedule and overloaded days before saving. No repeated automatic generation during sync.
- Android local reminders for upcoming assignments, quizzes and exams (notification permission must be granted).
- Offline local records with manually retried Supabase sync. Uploaded document bytes require internet.
- Manual Google Drive full backup/restore of records and up to 25 MB of document/photo bytes, once OAuth has been configured.

## Windows installation

**Do not delete your older project or uninstall the current APK yet.** Back up the current project and any unsynchronized data first.

1. Extract this ZIP into **`E:\mad\StudyPulse_Mobile_Pro`**. Keep it on the E: drive because your Flutter pub cache is on E: too.
2. Open this folder in VS Code.
3. In a PowerShell terminal, run:

   ```powershell
   cd "E:\mad\StudyPulse_Mobile_Pro"
   powershell -ExecutionPolicy Bypass -File .\setup_windows.ps1
   ```

4. Open your **existing Supabase project** at `https://jljkjtxcdfqcgtamkvjl.supabase.co` in the Supabase dashboard.
5. Run the entire **`supabase/SETUP.sql`** in SQL Editor. This creates the private `sp2_materials` bucket, its policies and `sp2_items` if needed. Do not run any legacy database reset scripts.
6. In the app, sign in using the same Supabase account as the older app.
7. Test saving a book locally, syncing, and uploading one PDF. Tap the uploaded file to verify it opens.
8. Open a book → select Study documents → choose that book and upload a structured text PDF/DOCX/PPTX → review suggested topics → generate an exam plan from that book.
9. Grant Android notification permission via the bell in the app bar. Add an assignment or quiz due in the future, and test a reminder with the app backgrounded.
10. Set up Google Cloud OAuth for Drive backup, see `GOOGLE_DRIVE_SETUP.md`.

### Build APK without Google Drive OAuth

```powershell
cd "E:\mad\StudyPulse_Mobile_Pro"
powershell -ExecutionPolicy Bypass -File .\setup_windows.ps1 -BuildApk
```

### Build APK WITH Google Drive OAuth

```powershell
cd "E:\mad\StudyPulse_Mobile_Pro"
powershell -ExecutionPolicy Bypass -File .\setup_windows.ps1 -BuildApk -WebClientId "YOUR_WEB_CLIENT_ID.apps.googleusercontent.com"
```

APK output: `build\app\outputs\flutter-apk\app-release.apk`

## Install behavior and data preservation

- Package name is generated as `com.example.study_pulse_mobile` to match the original StudyPulse Mobile Rebuild default package name.
- The same local shared preferences keys `study_pulse_v2_<userId>_items` and `_queue` are reused. This allows existing local JSON records to be loaded **if you install over the old app without clearing data** and the Android signing certificate matches.
- If the APK reports `App not installed`, the signing key or package ID may differ. **Do not uninstall the old APK without exporting or syncing the saved data first.**
- Material read and photo viewing use a private Supabase Storage bucket and need a network connection.

## Study-plan limitations

Topic extraction uses rules, not AI: good for headings in structured files. Scanned/image-only PDFs have no selectable text and require OCR, which is not included. If no headings are detected, create topics manually. The planner schedules sessions before the chosen exam date, loads existing pending plans in that book, and flags overloads. It does not invent chapter summaries or quiz questions from arbitrary content.

## Notification limitations

Notifications are scheduled as **inexact** Android local alarms, normally at 9 AM the day before the due date, or at 8 AM on the due date when the previous time has passed. Android battery optimization, notification settings, and device manufacturer restrictions can delay or suppress delivery. There is no guarantee of exact delivery time. This build does not include Firebase push notifications. Grant notification permission in the bell icon.

## Backup limitations

The `drive.file` OAuth scope allows accessing backups created by the app, not browsing all Drive files. Google OAuth **requires** a Web client ID and Android OAuth client registered to your Android application ID and APK signing SHA-1. App data backup includes records and up to 25 MB of uploaded documents and student photo. Bigger backups require a different strategy. The backup data is not end-to-end encrypted beyond Google Drive's standard protections.

## Troubleshooting

- `StorageException ... Bucket not found`: verify `supabase/SETUP.sql` was run in the same Supabase project configured in `lib/main.dart`.
- `403` Storage: confirm you're signed in and RLS policies match the `userId/uuid.ext` Storage path.
- `flutter analyze` errors: stop APK build, share the entire analyzer output.
- Kotlin `different roots`: keep the project at E: because `PUB_CACHE` uses E:, then `flutter clean` and rebuild.
- `Google Drive backup failed`: complete OAuth registration, register APK signing SHA-1, use `-WebClientId` build switch.
- No notifications: grant permission and test a future due date with notifications enabled.
- Photo not showing offline: the app displays a placeholder because photo files are fetched securely from Supabase Storage.

## Verified source references

- File Picker 13 API: https://pub.dev/packages/file_picker/versions/13.4.0
- Flutter local notifications Android config: https://pub.dev/packages/flutter_local_notifications
- PDF viewer: https://pub.dev/packages/pdfrx/versions/2.13.0
- Supabase Storage security: https://supabase.com/docs/guides/storage/security/access-control
