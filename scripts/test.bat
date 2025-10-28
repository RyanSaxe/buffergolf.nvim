@echo off
REM Simple Windows test runner with optional coverage reporting

REM Clean up old coverage files
del /Q luacov.stats.out 2>nul
del /Q luacov.report.out 2>nul

REM Run tests using mini.test via the minit.lua bootstrap
REM Coverage is always enabled if luacov is available
nvim -l tests/minit.lua --minitest
set EXIT_CODE=%errorlevel%

REM Show coverage report if requested and tests passed
if "%1"=="--coverage" (
    if %EXIT_CODE% equ 0 (
        echo.
        echo Coverage Report:
        echo ================

        if exist luacov.report.out (
            REM Show summary from the report
            powershell -Command "Get-Content luacov.report.out | Select-Object -Last 20"
        ) else (
            echo No coverage report generated. You may need to install luacov.
            echo Install with: luarocks install luacov
        )
    )
)

exit /b %EXIT_CODE%