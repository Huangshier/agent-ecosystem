[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet("minimal", "recommended", "full", "dev")]
    [string]$Profile = "recommended",

    [string]$TargetDir = (Join-Path $HOME ".agents"),

    [switch]$Copy,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptDir
$targetRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TargetDir)

$kernelSkills = @(
    "project-bootstrap",
    "project-context-gate",
    "workflow-spec-lite",
    "memory-governance"
)

function Assert-PathInsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if (-not ($fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith($fullRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Refusing to modify path outside target root: $fullPath"
    }
}

function Get-PublicSkillNames {
    param([string]$SelectedProfile)

    if ($SelectedProfile -eq "minimal") {
        return @("project-bootstrap")
    }

    if ($SelectedProfile -in @("recommended", "full", "dev")) {
        return @($kernelSkills)
    }

    throw "Unsupported profile: $SelectedProfile"
}

function Copy-DirectoryTree {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function Install-Directory {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source not found for ${Name}: $Source"
    }

    Assert-PathInsideRoot -Path $Destination -Root $targetRoot

    if (Test-Path -LiteralPath $Destination) {
        if (-not $Force.IsPresent) {
            throw "Destination already exists for ${Name}: $Destination. Re-run with -Force to replace it."
        }
        if ($PSCmdlet.ShouldProcess($Destination, "Remove existing install target")) {
            Remove-Item -LiteralPath $Destination -Recurse -Force
        }
    }

    $mode = "copy"
    if ($PSCmdlet.ShouldProcess($Destination, "Install ${Name}")) {
        if ($Copy.IsPresent) {
            Copy-DirectoryTree -Source $Source -Destination $Destination
        }
        else {
            try {
                $parent = Split-Path -Parent $Destination
                New-Item -ItemType Directory -Force -Path $parent | Out-Null
                $itemType = if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) { "Junction" } else { "SymbolicLink" }
                New-Item -ItemType $itemType -Path $Destination -Target $Source -ErrorAction Stop | Out-Null
                $mode = $itemType.ToLowerInvariant()
            }
            catch {
                Write-Warning "Link install failed for ${Name}; falling back to copy. $($_.Exception.Message)"
                Copy-DirectoryTree -Source $Source -Destination $Destination
                $mode = "copy-fallback"
            }
        }
    }

    return [ordered]@{
        name = $Name
        source = $Source
        destination = $Destination
        mode = $mode
    }
}

$skillNames = @(Get-PublicSkillNames -SelectedProfile $Profile)
$items = New-Object 'System.Collections.Generic.List[object]'

New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null

$hubSource = Join-Path $repoRoot "knowledge-hub"
$hubDestination = Join-Path $targetRoot "knowledge-hub"
$items.Add((Install-Directory -Name "knowledge-hub" -Source $hubSource -Destination $hubDestination))

foreach ($skillName in $skillNames) {
    $skillSource = Join-Path $repoRoot "skills\$skillName"
    $skillDestination = Join-Path $targetRoot "skills\$skillName"
    $items.Add((Install-Directory -Name "skills/$skillName" -Source $skillSource -Destination $skillDestination))
}

$manifest = [ordered]@{
    schema_version = 1
    profile = $Profile
    installed_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    source_root = $repoRoot
    target_dir = $targetRoot
    link_preferred = -not $Copy.IsPresent
    skills = @($skillNames)
    items = @($items.ToArray())
}

$manifestPath = Join-Path $targetRoot "install-manifest.json"
if ($PSCmdlet.ShouldProcess($manifestPath, "Write install manifest")) {
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
}

Write-Host "Installed Agent Ecosystem profile '$Profile' to: $targetRoot"
Write-Host "Skills: $($skillNames -join ', ')"
Write-Host "Manifest: $manifestPath"
