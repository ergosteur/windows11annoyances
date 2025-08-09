@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Windows 11 per-user tweaks → Default + ALL existing users

:: --- Admin check ---
net session >nul 2>&1
if errorlevel 1 (
  echo [!] Please run this script as Administrator.
  pause
  exit /b 1
)

:: ---------- Subroutine: apply a block of HKCU-style tweaks to a given hive root ----------
:: Usage: call :apply HKU\SomeHiveRoot
:apply
set "ROOT=%~1"

:: Advertising ID / Tailored experiences
reg add "%ROOT%\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled /t REG_DWORD /d 0 /f >nul
reg add "%ROOT%\Software\Microsoft\Windows\CurrentVersion\Privacy" /v TailoredExperiencesWithDiagnosticDataEnabled /t REG_DWORD /d 0 /f >nul

:: Content Delivery / Suggestions / Spotlight
set "CDM=%ROOT%\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
for %%V in (
  ContentDeliveryAllowed
  OemPreInstalledAppsEnabled
  PreInstalledAppsEnabled
  PreInstalledAppsEverEnabled
  SilentInstalledAppsEnabled
  SystemPaneSuggestionsEnabled
  SoftLandingEnabled
  RotatingLockScreenEnabled
  RotatingLockScreenOverlayEnabled
  SubscribedContent-338387Enabled
  SubscribedContent-338388Enabled
  SubscribedContent-338389Enabled
  SubscribedContent-338393Enabled
  SubscribedContent-338394Enabled
  SubscribedContent-338396Enabled
  SubscribedContent-353694Enabled
  SubscribedContent-353696Enabled
) do reg add "%CDM%" /v %%V /t REG_DWORD /d 0 /f >nul

:: File Explorer promos (does NOT break OneDrive sync)
reg add "%ROOT%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowSyncProviderNotifications /t REG_DWORD /d 0 /f >nul

:: Hide Widgets button on the taskbar
reg add "%ROOT%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarDa /t REG_DWORD /d 0 /f >nul

:: Search: disable highlights/doodles
reg add "%ROOT%\Software\Policies\Microsoft\Windows\Windows Search" /v EnableDynamicContentInWSB /t REG_DWORD /d 0 /f >nul

:: Mute welcome/tips post-update
reg add "%ROOT%\Software\Microsoft\Siuf\Rules" /v NumberOfSIUFInPeriod /t REG_DWORD /d 0 /f >nul
reg add "%ROOT%\Software\Microsoft\Siuf\Rules" /v PeriodInNanoSeconds /t REG_DWORD /d 0 /f >nul

exit /b 0


:: ---------- 1) Stamp Default User (future profiles) ----------
set "NTUSER=%SystemDrive%\Users\Default\NTUSER.DAT"
set "DEFHIVE=HKU\DefUserTmp"

echo.
echo [+] Updating Default User profile (for all NEW accounts)...
if not exist "%NTUSER%" (
  echo [!] Could not find %NTUSER% — skipping Default User.
) else (
  reg load "%DEFHIVE%" "%NTUSER%" >nul
  if errorlevel 1 (
    echo [!] Failed to load Default User hive (maybe locked?). Skipping.
  ) else (
    call :apply "%DEFHIVE%"
    reg unload "%DEFHIVE%" >nul
    echo [✓] Default User updated.
  )
)

:: ---------- 2) Update all CURRENTLY-LOADED user SIDs under HKU ----------
echo.
echo [+] Updating all currently-loaded user hives (active logons)...
for /f "skip=2 tokens=1" %%S in ('reg query HKU 2^>nul') do (
  set "SID=%%S"
  :: Match real user SIDs: S-1-5-21-... (exclude *_Classes)
  echo !SID! | findstr /r /b /c:"HKEY_USERS\\S-1-5-21-" >nul || goto :_skipLoaded
  echo !SID! | findstr /i "_Classes" >nul && goto :_skipLoaded

  call :apply "!SID!"
  echo [✓] Updated loaded hive: !SID!

  :_skipLoaded
)

:: ---------- 3) Update OFFLINE user profiles by loading NTUSER.DAT for each ----------
echo.
echo [+] Updating offline user hives in C:\Users\* ...
for /d %%D in ("%SystemDrive%\Users\*") do (
  set "U=%%~nxD"

  :: Skip known non-user dirs
  if /I "!U!"=="Default"       goto :_next
  if /I "!U!"=="Default User"  goto :_next
  if /I "!U!"=="Public"        goto :_next
  if /I "!U!"=="All Users"     goto :_next
  if /I "!U!"=="Administrator" goto :_maybe   :: (optional: keep or skip admin)
  goto :_maybe

  :_maybe
  if exist "%%D\NTUSER.DAT" (
    :: If this profile is already loaded (active session), it was handled above; skip loading.
    set "ALREADY="
    for /f "skip=2 tokens=1" %%S in ('reg query HKU 2^>nul') do (
      echo %%S | findstr /r /c:"HKEY_USERS\\S-1-5-21-" >nul || goto :_cont1
      reg query "%%S\Volatile Environment" >nul 2>&1 && (
        reg query "%%S\Software\Microsoft\Windows\CurrentVersion\Explorer" >nul 2>&1 && (
          for /f "tokens=3*" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" /s /v ProfileImagePath ^| findstr /i /c:"\Users\!U!"') do (
            rem we only need a rough guard; rely on the loaded-SID pass above
            set "ALREADY=1"
          )
        )
      )
      :_cont1
    )
    if defined ALREADY goto :_next

    set "TMPHIVE=HKU\Tmp_!U!"
    reg load "!TMPHIVE!" "%%D\NTUSER.DAT" >nul
    if not errorlevel 1 (
      call :apply "!TMPHIVE!"
      reg unload "!TMPHIVE!" >nul
      echo [✓] Updated offline profile: !U!
    ) else (
      echo [!] Could not load hive for !U! (maybe in use). Skipping.
    )
  )
  :_next
)

echo.
echo [✓] Done. New users and existing profiles have been updated.
echo     (Sign out/in or reboot to see all effects.)
endlocal
