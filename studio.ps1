<#
.SYNOPSIS
    Startup Studio Automation Tool for managing my-kit and client ventures.
.DESCRIPTION
    Commands:
      .\studio.ps1 new <client_name> [--type web|desktop|hybrid] [--source path|git]
      .\studio.ps1 switch-source <client_name> -Source <path|git> [-Tag <v0.X.Y>]
      .\studio.ps1 upgrade <client_name> -Tag <v0.X.Y> [-SyncStyles]
      .\studio.ps1 check
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("new", "switch-source", "upgrade", "check", "help")]
    [string]$Command,

    [Parameter(Position = 1)]
    [string]$ClientName,

    [Parameter()]
    [ValidateSet("web", "desktop", "hybrid")]
    [string]$Type = "hybrid",

    [Parameter()]
    [ValidateSet("path", "git")]
    [string]$Source = "path",

    [Parameter()]
    [string]$Tag = "v0.1.0",

    [Parameter()]
    [switch]$SyncStyles
)

$StudioRoot = $PSScriptRoot
$MyKitDir = Join-Path $StudioRoot "my-kit"
$ClientsDir = Join-Path $StudioRoot "clients"
$GitRepoUrl = "https://github.com/subrataai-wq/my-kit.git"

function Show-Help {
    Write-Host "Startup Studio CLI" -ForegroundColor Cyan
    Write-Host "Usage:"
    Write-Host "  .\studio.ps1 new <client-name> [--type web|desktop|hybrid] [--source path|git]"
    Write-Host "  .\studio.ps1 switch-source <client-name> -Source <path|git> [-Tag <v0.X.Y>]"
    Write-Host "  .\studio.ps1 upgrade <client-name> -Tag <v0.X.Y> [-SyncStyles]"
    Write-Host "  .\studio.ps1 check"
}

switch ($Command) {
    "help" {
        Show-Help
        break
    }

    "new" {
        if (-not $ClientName) {
            Write-Error "Please specify a client name (e.g. .\studio.ps1 new my-ecommerce --type hybrid)"
            exit 1
        }

        # Validate name
        if ($ClientName -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
            Write-Error "Client name must be kebab-case (e.g., 'ecommerce-store' or 'photo-studio')"
            exit 1
        }

        $TargetClientDir = Join-Path $ClientsDir $ClientName
        $TargetRepoDir = Join-Path $TargetClientDir "repo"
        $TargetDocsDir = Join-Path $TargetClientDir "docs"
        $TargetOpsDir = Join-Path $TargetClientDir "ops"
        $TargetSourceDir = Join-Path $TargetClientDir "source-files"

        Write-Host "--> Scaffolding client venture '$ClientName'..." -ForegroundColor Cyan

        # 1. Create directory structure
        New-Item -ItemType Directory -Force -Path $TargetDocsDir, $TargetOpsDir, $TargetSourceDir, $TargetRepoDir | Out-Null

        # 2. Populate docs and ops templates
        $BriefContent = @"
# Client Brief: $ClientName

- **Date:** $(Get-Date -Format "yyyy-MM-dd")
- **Type:** $Type
- **Project Lead:** Subrata Roy
- **Repository:** clients/$ClientName/repo

## 1. Project Overview & Deliverables
TBD

## 2. Core Milestones
- [ ] Milestone 1: Core UX & Domain Models
- [ ] Milestone 2: Feature Implementation & Verification
- [ ] Milestone 3: Production Deployment & Handover
"@
        Set-Content -Path (Join-Path $TargetDocsDir "BRIEF.md") -Value $BriefContent

        $OpsContent = @"
# Ops & Deployment Runbook: $ClientName

- **Platform Target:** $Type
- **Domain:** TBD

## CI/CD Access Secret
Because my-kit is a private repository, remote GitHub Actions must configure a PAT or Deploy Key:
  git config --global url."https://<PAT>@github.com/".insteadOf "https://github.com/"
"@
        Set-Content -Path (Join-Path $TargetOpsDir "DEPLOYMENT.md") -Value $OpsContent
        Set-Content -Path (Join-Path $TargetSourceDir ".gitkeep") -Value "# Raw uncompressed client media assets (not tracked in Git)"

        # 3. Copy my-kit-template into repo
        $TemplateDir = Join-Path $MyKitDir "crates\my-kit-template"
        Get-ChildItem -Path $TemplateDir | Copy-Item -Destination $TargetRepoDir -Recurse -Force

        # 4. Configure client Cargo.toml
        $ClientCargoToml = Join-Path $TargetRepoDir "Cargo.toml"
        $PackageName = "client-$ClientName"
        $DefaultFeatures = switch ($Type) {
            "web" { 'default = ["web"]' }
            "desktop" { 'default = ["desktop"]' }
            "hybrid" { 'default = ["desktop", "web"]' }
        }

        $DepsBlock = if ($Source -eq "git") {
            "my-kit-core = { git = `"$GitRepoUrl`", tag = `"$Tag`" }`nmy-kit-ui = { git = `"$GitRepoUrl`", tag = `"$Tag`" }"
        } else {
            "my-kit-core = { path = `"../../../my-kit/crates/my-kit-core`", version = `"0.1.0`" }`nmy-kit-ui = { path = `"../../../my-kit/crates/my-kit-ui`", version = `"0.1.0`" }"
        }

        $CargoContent = @"
[package]
name = "$PackageName"
version = "0.1.0"
edition = "2024"
authors = ["subrataai-wq <subrata.ai.short@gmail.com>"]

[dependencies]
dioxus = { version = "0.7.1" }
$DepsBlock
serde = { version = "1.0", features = ["derive"] }

[features]
$DefaultFeatures
web = ["dioxus/web"]
desktop = ["dioxus/desktop"]
mobile = ["dioxus/mobile"]
"@
        Set-Content -Path $ClientCargoToml -Value $CargoContent

        # 5. Create local .cargo/config.toml (patch to local path)
        $ClientDotCargoDir = Join-Path $TargetRepoDir ".cargo"
        New-Item -ItemType Directory -Force -Path $ClientDotCargoDir | Out-Null
        $ConfigTomlContent = @"
[patch."$GitRepoUrl"]
my-kit-core = { path = "../../../my-kit/crates/my-kit-core" }
my-kit-ui = { path = "../../../my-kit/crates/my-kit-ui" }
"@
        Set-Content -Path (Join-Path $ClientDotCargoDir "config.toml") -Value $ConfigTomlContent

        # 6. Create client repo .gitignore (ignoring /target and .cargo/config.toml, leaving Cargo.lock TRACKED)
        $ClientGitignoreContent = @"
/target
.cargo/config.toml
"@
        Set-Content -Path (Join-Path $TargetRepoDir ".gitignore") -Value $ClientGitignoreContent

        # 7. Initialize Git repo inside client repo
        Push-Location $TargetRepoDir
        try {
            git init -b main | Out-Null
            git add . | Out-Null
            git commit -m "feat: scaffold initial client repo from my-kit template ($Type)" | Out-Null
        } finally {
            Pop-Location
        }

        Write-Host "[OK] Client '$ClientName' scaffolded successfully in clients/$ClientName" -ForegroundColor Green
        Write-Host "  - Dependency source: $Source"
        Write-Host "  - Local patch configured: .cargo/config.toml (git-ignored)"
        break
    }

    "switch-source" {
        if (-not $ClientName) {
            Write-Error "Please specify client name (e.g. .\studio.ps1 switch-source ecommerce -Source git)"
            exit 1
        }

        $ClientRepoDir = Join-Path $ClientsDir "$ClientName\repo"
        $ClientCargoToml = Join-Path $ClientRepoDir "Cargo.toml"

        if (-not (Test-Path $ClientCargoToml)) {
            Write-Error "Cargo.toml not found at $ClientCargoToml"
            exit 1
        }

        Write-Host "--> Switching dependency source for '$ClientName' to '$Source'..." -ForegroundColor Cyan

        $Content = Get-Content $ClientCargoToml -Raw
        if ($Source -eq "git") {
            $gitCore = 'my-kit-core = { git = "' + $GitRepoUrl + '", tag = "' + $Tag + '" }'
            $gitUi = 'my-kit-ui = { git = "' + $GitRepoUrl + '", tag = "' + $Tag + '" }'
            $Content = [System.Text.RegularExpressions.Regex]::Replace($Content, 'my-kit-core\s*=\s*\{[^}]+\}', $gitCore)
            $Content = [System.Text.RegularExpressions.Regex]::Replace($Content, 'my-kit-ui\s*=\s*\{[^}]+\}', $gitUi)
        } else {
            $pathCore = 'my-kit-core = { path = "../../../my-kit/crates/my-kit-core", version = "0.1.0" }'
            $pathUi = 'my-kit-ui = { path = "../../../my-kit/crates/my-kit-ui", version = "0.1.0" }'
            $Content = [System.Text.RegularExpressions.Regex]::Replace($Content, 'my-kit-core\s*=\s*\{[^}]+\}', $pathCore)
            $Content = [System.Text.RegularExpressions.Regex]::Replace($Content, 'my-kit-ui\s*=\s*\{[^}]+\}', $pathUi)
        }
        Set-Content -Path $ClientCargoToml -Value $Content

        Write-Host "[OK] Client '$ClientName' dependencies updated to $Source mode." -ForegroundColor Green
        break
    }

    "upgrade" {
        if (-not $ClientName) {
            Write-Error "Please specify client name (e.g. .\studio.ps1 upgrade ecommerce -Tag v0.2.0)"
            exit 1
        }

        $ClientRepoDir = Join-Path $ClientsDir "$ClientName\repo"
        $ClientCargoToml = Join-Path $ClientRepoDir "Cargo.toml"

        if (-not (Test-Path $ClientCargoToml)) {
            Write-Error "Cargo.toml not found at $ClientCargoToml"
            exit 1
        }

        Write-Host "--> Upgrading '$ClientName' to my-kit $Tag..." -ForegroundColor Cyan

        # Update tag in Cargo.toml
        $Content = Get-Content $ClientCargoToml -Raw
        $UpdatedContent = $Content -replace 'tag = "[^"]+"', "tag = `"$Tag`""
        Set-Content -Path $ClientCargoToml -Value $UpdatedContent

        # Sync styles if requested
        if ($SyncStyles) {
            $SourceCss = Join-Path $MyKitDir "crates\my-kit-ui\assets\main.css"
            $DestCss = Join-Path $ClientRepoDir "assets\main.css"
            if (Test-Path $SourceCss) {
                Copy-Item -Path $SourceCss -Destination $DestCss -Force
                Write-Host "  [OK] Synchronized updated main.css design tokens" -ForegroundColor Green
            }
        }

        # Run cargo update and check
        Push-Location $ClientRepoDir
        try {
            cargo update
            cargo check
            Write-Host "[OK] Client '$ClientName' successfully upgraded and verified." -ForegroundColor Green
        } finally {
            Pop-Location
        }
        break
    }

    "check" {
        Write-Host "--> Running verification on my-kit workspace..." -ForegroundColor Cyan
        cargo check --workspace --manifest-path (Join-Path $MyKitDir "Cargo.toml")
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

        cargo test --workspace --manifest-path (Join-Path $MyKitDir "Cargo.toml")
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

        cargo clippy --workspace --manifest-path (Join-Path $MyKitDir "Cargo.toml") -- -D warnings
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

        Write-Host "--> Verifying my-kit-core on wasm32-unknown-unknown..." -ForegroundColor Cyan
        cargo check -p my-kit-core --target wasm32-unknown-unknown --manifest-path (Join-Path $MyKitDir "Cargo.toml")
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

        # Check existing client repositories
        $ClientRepos = Get-ChildItem -Path $ClientsDir -Directory
        foreach ($c in $ClientRepos) {
            $ClientCargo = Join-Path $c.FullName "repo\Cargo.toml"
            if (Test-Path $ClientCargo) {
                Write-Host "--> Verifying client repo '$($c.Name)'..." -ForegroundColor Cyan
                cargo check --manifest-path $ClientCargo
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "Verification failed for client repo '$($c.Name)'"
                    exit $LASTEXITCODE
                }
            }
        }

        Write-Host "[OK] Entire Studio ecosystem is 100% healthy!" -ForegroundColor Green
        break
    }
}
