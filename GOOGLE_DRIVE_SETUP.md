# Google Drive configuration — required before Drive backup works

Google Drive cannot be made functional by embedding only a Supabase URL or anon/publishable key. Google requires a matching OAuth application registration.

1. Open https://console.cloud.google.com and select a Google Cloud project.
2. Enable **Google Drive API**.
3. Configure Google Auth Platform/consent screen, add the Drive `drive.file` scope and any testing accounts.
4. Create a **Web OAuth client ID**. Keep the ID for `-WebClientId` in the build command.
5. Create an **Android OAuth client ID** for package `com.example.study_pulse_mobile` and the SHA-1 certificate used to sign your Android APK.
6. For the Flutter-generated debug keystore, inspect SHA-1 with:

   ```powershell
   keytool -list -v -alias androiddebugkey -keystore "$env:USERPROFILE\.android\debug.keystore" -storepass android -keypass android
   ```

   Release APKs may be signed with a different certificate. Register the correct SHA-1 for **the APK actually installed on your phone**. Do not rely on the debug SHA-1 for a production-signed release.
7. Build with:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup_windows.ps1 -BuildApk -WebClientId "YOUR_WEB_CLIENT_ID.apps.googleusercontent.com"
   ```

8. Install the APK, sign in to StudyPulse with Supabase, go to **More → Google Drive full backup → Back up**, choose a Google account and approve the scope.
9. Verify a `StudyPulse_Full_*.json` file appeared in Google Drive. Test **Restore** from the same Supabase user account.

The feature is Android only in this source. Drive backup is manual, not automatic. Ensure file sizes meet the 25 MB document limit and check internet access. Uploaded JSON contains study records and base64 file data. Use Google account security controls appropriate to your data.
