@echo off
REM Double-click: pulls the latest policy files from Git, then applies all 3 to Secrets Manager.
REM Uses "conjur policy update": adds and changes, never deletes what a file leaves out.
REM Never use "policy replace": it replaces a whole branch (it would delete the authenticators).
REM Needs: Conjur CLI logged in as admin (conjur login -i admin). Git is optional.
setlocal
cd /d "%~dp0"
echo == Idira Secrets Manager: update policies
where git >nul 2>nul && (echo == git pull & git -C .. pull --ff-only || echo    warn: git pull failed, using the local files)
where conjur >nul 2>nul || (echo ERROR: Conjur CLI not found on PATH & goto :fail)
conjur whoami >nul 2>nul || (echo ERROR: not logged in. Run: conjur login -i admin & goto :fail)
call :apply root root.yml           || goto :fail
call :apply prod prod.yml           || goto :fail
call :apply root authenticators.yml || goto :fail
echo.
echo == Done: all 3 policies applied. Nothing was deleted.
pause
exit /b 0

:apply
echo.
echo == conjur policy update -b %1 -f %2
conjur policy update -b %1 -f %2
exit /b %errorlevel%

:fail
echo.
echo == STOPPED. The steps after this one were not applied.
pause
exit /b 1
