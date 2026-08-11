# Repository Guidelines

## Project Structure & Module Organization

`M365PSProfile.psm1` contains the module implementation; `M365PSProfile.psd1` defines metadata, dependencies, and the exported command surface. Keep those files synchronized when adding or removing public functions. Pester coverage lives in `Tests/M365PSProfile.Tests.ps1`. User documentation and release notes are in `README.md`, `Deployment.md`, and `CHANGELOG.md`; root-level PNG files are README screenshots.

## Build, Test, and Development Commands

Run commands from the repository root in PowerShell:

- `Import-Module .\M365PSProfile.psd1 -Force` loads the local module for manual testing.
- `Test-ModuleManifest .\M365PSProfile.psd1` validates manifest syntax and metadata.
- `Invoke-Pester -Path .\Tests -Output Detailed` runs the full automated test suite.
- `Invoke-ScriptAnalyzer -Path .\M365PSProfile.psm1 -ExcludeRule PSAvoidUsingWriteHost,PSAvoidGlobalVars` applies the repository's documented analyzer exceptions.

There is no compilation step. Install development tools with `Install-PSResource -Name Pester,PSScriptAnalyzer -Scope CurrentUser` when needed.

## Coding Style & Naming Conventions

Use four spaces, braces on their own lines, and the surrounding PowerShell style. Name functions with approved `Verb-Noun` pairs (for example, `Get-M365StandardModule`) and parameters and variables in PascalCase. Public functions need comment-based help, a manifest entry under `FunctionsToExport`, and matching export tests. Prefer full cmdlet and parameter names over aliases. Preserve PowerShell 5.1 and PowerShell Core compatibility.

## Testing Guidelines

Use Pester and name new files `*.Tests.ps1`. Organize scenarios with `Describe`, `Context`, and behavior-focused `It` blocks. Add regression tests for changed behavior and validate parsing, manifest exports, imports, help, and command results as applicable. No coverage threshold is defined. For compatibility-sensitive changes, test both Windows PowerShell 5.1 and current PowerShell 7.

## Commit & Pull Request Guidelines

History favors short, action-led subjects such as `Add Changelog` and `Fix Script Analyzer Issues`; keep commits focused and avoid cosmetic-only changes. Branch from `develop` and open pull requests back to `develop`. PR descriptions should state the problem, solution, tests run, and any documentation impact; link the relevant issue and include updated screenshots when user-facing output changes.

## Security & Configuration Tips

Never commit PowerShell Gallery API keys or environment-specific paths. Installation, uninstallation, publishing, and profile-editing commands can modify the host: use an isolated test environment, review targets, and use `-WhatIf` where supported.
