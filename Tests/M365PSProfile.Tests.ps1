# Pester tests for M365PSProfile
# Run from repo root: Invoke-Pester

$ErrorActionPreference = 'Stop'

$script:ExpectedExports = @(
    'Install-M365Module',
    'Uninstall-M365Module',
    'Get-M365StandardModule',
    'Add-M365PSProfile',
    'Disconnect-All',
    'Set-WindowTitle'
)

BeforeAll {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

    $script:ManifestPath = Join-Path $repoRoot 'M365PSProfile.psd1'
    $script:ModulePath = Join-Path $repoRoot 'M365PSProfile.psm1'
}

Describe 'M365PSProfile' {
    It 'Manifest file exists' {
        $ManifestPath | Should -Exist
    }

    It 'Module file exists' {
        $ModulePath | Should -Exist
    }

    It 'Module script parses without syntax errors' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($ModulePath, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It 'Manifest exports the expected functions' {
        $data = Import-PowerShellDataFile -Path $ManifestPath
        $data.FunctionsToExport | Should -Not -BeNullOrEmpty

        foreach ($name in $script:ExpectedExports) {
            $data.FunctionsToExport | Should -Contain $name
        }
    }

    Context 'Import and command surface' {
        BeforeAll {
            $SkipImportBecause = $null

            $requiredModuleName = 'Microsoft.PowerShell.PSResourceGet'
            $requiredModuleMinVersion = [version]'1.2.0'

            $available = Get-Module -Name $requiredModuleName -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
            if (-not $available -or $available.Version -lt $requiredModuleMinVersion) {
                $SkipImportBecause = "Required dependency '$requiredModuleName' >= $requiredModuleMinVersion is not available on this machine."
            }
        }

        AfterAll {
            Remove-Module -Name 'M365PSProfile' -Force -ErrorAction SilentlyContinue
        }

        It 'Can import the local module manifest' {
            if ($SkipImportBecause) {
                Set-ItResult -Skipped -Because $SkipImportBecause
                return
            }

            Import-Module -Name $ManifestPath -Force -ErrorAction Stop
            (Get-Module -Name 'M365PSProfile') | Should -Not -BeNullOrEmpty
        }

        It 'Exports expected commands after import' {
            if ($SkipImportBecause) {
                Set-ItResult -Skipped -Because $SkipImportBecause
                return
            }

            foreach ($name in $script:ExpectedExports) {
                Get-Command -Name $name -Module 'M365PSProfile' -ErrorAction Stop | Should -Not -BeNullOrEmpty
            }
        }

        It 'Get-M365StandardModule returns a non-empty array' {
            if ($SkipImportBecause) {
                Set-ItResult -Skipped -Because $SkipImportBecause
                return
            }

            $modules = @(Get-M365StandardModule)
            $modules | Should -Not -BeNullOrEmpty
            $modules.Count | Should -BeGreaterThan 0
            $modules | Should -Contain 'Microsoft.Graph'
            $modules | Should -Contain 'M365PSProfile'
        }

        It 'Each exported function has help available' {
            if ($SkipImportBecause) {
                Set-ItResult -Skipped -Because $SkipImportBecause
                return
            }

            foreach ($name in $script:ExpectedExports) {
                $help = Get-Help -Name $name -ErrorAction Stop
                $help.Synopsis | Should -Not -BeNullOrEmpty
            }
        }

        It 'Returns control to the caller when updates are disabled in VS Code' {
            if ($SkipImportBecause) {
                Set-ItResult -Skipped -Because $SkipImportBecause
                return
            }

            $job = Start-Job -ScriptBlock {
                param($Path)

                $env:TERM_PROGRAM = 'vscode'
                $global:PROFILE = Join-Path ([System.IO.Path]::GetTempPath()) 'M365PSProfile-test-profile.ps1'
                Import-Module -Name $Path -Force
                Install-M365Module -Modules @() -AsciiArt $false
                'AFTER_CALL'
            } -ArgumentList $ManifestPath

            try {
                $job | Wait-Job | Out-Null
                $output = @(Receive-Job -Job $job -ErrorAction Stop)
                $output | Should -Contain 'AFTER_CALL'
            } finally {
                Remove-Job -Job $job -Force
            }
        }

        It 'Imports without errors when PROFILE is unavailable' {
            if ($SkipImportBecause) {
                Set-ItResult -Skipped -Because $SkipImportBecause
                return
            }

            $job = Start-Job -ScriptBlock {
                param($Path)

                Set-Variable -Name PROFILE -Value $null -Scope Global -Force
                $Error.Clear()
                Import-Module -Name $Path -Force
                [pscustomobject]@{
                    ErrorCount = $Error.Count
                    Loaded = $null -ne (Get-Module -Name M365PSProfile)
                }
            } -ArgumentList $ManifestPath

            try {
                $job | Wait-Job | Out-Null
                $result = @(Receive-Job -Job $job)[-1]
                $result.Loaded | Should -BeTrue
                $result.ErrorCount | Should -Be 0
            } finally {
                Remove-Job -Job $job -Force
            }
        }

        It 'Queries Microsoft.Entra submodules when the root module is absent' {
            if ($SkipImportBecause) {
                Set-ItResult -Skipped -Because $SkipImportBecause
                return
            }

            Mock -CommandName Get-InstalledPSResource -ModuleName M365PSProfile -MockWith {
                if ($Name -eq 'Microsoft.Entra.*') {
                    return [pscustomobject]@{ Name = 'Microsoft.Entra.Users'; Version = [version]'1.0.0'; Repository = 'PSGallery'; Scope = 'CurrentUser' }
                }

                return $null
            }
            Mock -CommandName Uninstall-PSResource -ModuleName M365PSProfile

            Uninstall-M365Module -Modules @('Microsoft.Entra') -Scope CurrentUser

            Should -Invoke -CommandName Get-InstalledPSResource -ModuleName M365PSProfile -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'Microsoft.Entra.*'
            }
        }

        It 'Uses the Microsoft.Entra wildcard for file-mode cleanup' {
            if ($SkipImportBecause) {
                Set-ItResult -Skipped -Because $SkipImportBecause
                return
            }

            Mock -CommandName Get-InstalledPSResource -ModuleName M365PSProfile -MockWith { return $null }
            Mock -CommandName Get-M365ModulePath -ModuleName M365PSProfile -MockWith { return 'TestDrive:\Modules' }
            Mock -CommandName Get-ChildItem -ModuleName M365PSProfile -MockWith { return @() }

            Uninstall-M365Module -Modules @('Microsoft.Entra') -Scope CurrentUser -FileMode

            Should -Invoke -CommandName Get-ChildItem -ModuleName M365PSProfile -Times 1 -Exactly -ParameterFilter {
                $Filter -eq 'Microsoft.Entra.*'
            }
        }

        It 'Updates PSResourceGet across a two-digit minor version boundary' {
            if ($SkipImportBecause) {
                Set-ItResult -Skipped -Because $SkipImportBecause
                return
            }

            Mock -CommandName Get-Process -ModuleName M365PSProfile -MockWith { return @() }
            Mock -CommandName Get-PSResourceRepository -ModuleName M365PSProfile -MockWith {
                [pscustomobject]@{ Name = 'PSGallery'; Trusted = $true; Uri = 'https://www.powershellgallery.com/api/v2' }
            }
            Mock -CommandName Get-InstalledPSResource -ModuleName M365PSProfile -MockWith {
                [pscustomobject]@{ Name = 'Microsoft.PowerShell.PSResourceGet'; Version = [version]'1.9.0'; Repository = 'PSGallery'; Scope = 'CurrentUser' }
            }
            Mock -CommandName Find-PSResource -ModuleName M365PSProfile -MockWith {
                [pscustomobject]@{ Name = 'Microsoft.PowerShell.PSResourceGet'; Version = [version]'1.10.0'; Repository = 'PSGallery' }
            }
            Mock -CommandName Install-PSResource -ModuleName M365PSProfile

            Install-M365Module -Modules @() -AsciiArt $false -RunInVSCode $true

            Should -Invoke -CommandName Install-PSResource -ModuleName M365PSProfile -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'Microsoft.PowerShell.PSResourceGet'
            }
        }

        It 'Checks and updates PSResourceGet in AllUsers scope' {
            if ($SkipImportBecause) {
                Set-ItResult -Skipped -Because $SkipImportBecause
                return
            }

            Mock -CommandName Get-Process -ModuleName M365PSProfile -MockWith { return @() }
            Mock -CommandName Get-PSResourceRepository -ModuleName M365PSProfile -MockWith {
                [pscustomobject]@{ Name = 'PSGallery'; Trusted = $true; Uri = 'https://www.powershellgallery.com/api/v2' }
            }
            Mock -CommandName Get-InstalledPSResource -ModuleName M365PSProfile -MockWith {
                [pscustomobject]@{ Name = 'Microsoft.PowerShell.PSResourceGet'; Version = [version]'1.9.0'; Repository = 'PSGallery'; Scope = 'AllUsers' }
            }
            Mock -CommandName Find-PSResource -ModuleName M365PSProfile -MockWith {
                [pscustomobject]@{ Name = 'Microsoft.PowerShell.PSResourceGet'; Version = [version]'1.10.0'; Repository = 'PSGallery' }
            }
            Mock -CommandName Install-PSResource -ModuleName M365PSProfile

            Install-M365Module -Modules @() -Scope AllUsers -AsciiArt $false -RunInVSCode $true

            Should -Invoke -CommandName Get-InstalledPSResource -ModuleName M365PSProfile -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'Microsoft.PowerShell.PSResourceGet' -and $Scope -eq 'AllUsers'
            }
            Should -Invoke -CommandName Install-PSResource -ModuleName M365PSProfile -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'Microsoft.PowerShell.PSResourceGet' -and $Scope -eq 'AllUsers'
            }
        }

        It 'Reinstalls PSResourceGet after removing multiple persisted versions' {
            if ($SkipImportBecause) {
                Set-ItResult -Skipped -Because $SkipImportBecause
                return
            }

            Mock -CommandName Get-Process -ModuleName M365PSProfile -MockWith { return @() }
            Mock -CommandName Get-PSResourceRepository -ModuleName M365PSProfile -MockWith {
                [pscustomobject]@{ Name = 'PSGallery'; Trusted = $true; Uri = 'https://www.powershellgallery.com/api/v2' }
            }
            Mock -CommandName Get-InstalledPSResource -ModuleName M365PSProfile -MockWith {
                @(
                    [pscustomobject]@{ Name = 'Microsoft.PowerShell.PSResourceGet'; Version = [version]'1.9.0'; Repository = 'PSGallery'; Scope = 'CurrentUser' }
                    [pscustomobject]@{ Name = 'Microsoft.PowerShell.PSResourceGet'; Version = [version]'1.8.0'; Repository = 'PSGallery'; Scope = 'CurrentUser' }
                )
            }
            Mock -CommandName Uninstall-M365Module -ModuleName M365PSProfile
            Mock -CommandName Install-PSResource -ModuleName M365PSProfile

            Install-M365Module -Modules @() -AsciiArt $false -RunInVSCode $true

            Should -Invoke -CommandName Uninstall-M365Module -ModuleName M365PSProfile -Times 1 -Exactly -ParameterFilter {
                $Modules -eq 'Microsoft.PowerShell.PSResourceGet' -and $Scope -eq 'CurrentUser' -and $FileMode
            }
            Should -Invoke -CommandName Install-PSResource -ModuleName M365PSProfile -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'Microsoft.PowerShell.PSResourceGet' -and $Scope -eq 'CurrentUser'
            }
        }

        It 'Disconnects cleanly when optional service modules are not loaded' {
            if ($SkipImportBecause) {
                Set-ItResult -Skipped -Because $SkipImportBecause
                return
            }

            $job = Start-Job -ScriptBlock {
                param($Path)

                $global:PROFILE = Join-Path ([System.IO.Path]::GetTempPath()) 'M365PSProfile-test-profile.ps1'
                Import-Module -Name $Path -Force
                $PSModuleAutoLoadingPreference = 'None'
                $Error.Clear()
                Disconnect-All 2>$null
                $Error.Count
            } -ArgumentList $ManifestPath

            try {
                $job | Wait-Job | Out-Null
                $errorCount = @(Receive-Job -Job $job)[-1]
                $errorCount | Should -Be 0
            } finally {
                Remove-Job -Job $job -Force
            }
        }
    }
}
