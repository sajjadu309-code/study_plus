# Android acceptance checklist

Run these tests on a real Android phone **before uninstalling your older app**:

1. Install the APK as an update (same package and signing key). If Android rejects it, do not uninstall the older app until you have backed up or synced all records.
2. Sign in with the original Supabase account.
3. Dashboard → edit student profile → save name, roll number and program. Repeat with a PNG or JPG photo. Confirm it appears on Dashboard.
4. More → choose each accent color and dark mode; close and reopen app. Confirm theme remains selected.
5. Books → Add book. Confirm saved without a network connection, then re-enable internet and tap Sync. Confirm it appears in `public.sp2_items`.
6. Books → My documents → choose a book and upload one readable PDF/DOCX/TXT. It should be saved to the private `sp2_materials` bucket. Open the file from its list.
7. When the app suggests headings, select 2–3. Confirm they appear inside the book and in Supabase `sp2_items` as `topic` records.
8. Books → Exam plan → select that book and an exam date at least 2 days away. Preview the generated sessions. Confirm sessions appear under Tasks → plan and no duplicates appear after cloud sync.
9. Tasks → assignment/quiz/exam → Add → choose a future date → Save. Tap the bell in the app bar to grant notifications. Confirm the system permission is enabled.
10. Test an upcoming deadline with the phone online and offline, app in foreground/background. The inexact alarm should appear around the scheduled time, subject to Android's restrictions.
11. More → Google Drive backup → Back up. This requires a configured OAuth Web Client ID + registered Android signing SHA-1. Confirm the `StudyPulse_Full_*.json` file appears in Google Drive.
12. On the **same signed-in Supabase account**, test restoring the Drive backup and verify book/topic/file records.

# Notes

- If uploads display `Bucket not found 404`, execute `supabase/SETUP.sql` **in the Supabase project used by this app**.
- A PDF with pictures but no selectable text cannot generate topics without OCR. Add topics manually.
- Android permissions and battery management can delay or suppress reminders.
- This ZIP is a source project, not a precompiled/tested APK.
