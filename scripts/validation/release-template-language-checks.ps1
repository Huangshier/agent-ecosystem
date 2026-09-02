# release-template-language-checks.ps1
# Extracted from scripts/validate-release.ps1 Invoke-ReleaseValidationLanguageTemplateChecks (Phase 3).
# Runs bilingual public/private routing guidance checks.
# Depends on: release-test-helper.ps1 (Add-Check, Get-FileText, Get-MissingRequiredText), path-guard.ps1 (Join-PathParts).
# Scope: script-level $repoRoot, $script:evidence, $checks.

# Invoke-ReleaseTemplateLanguageChecks: No parameters; runs bilingual public/private routing
# guidance checks in the original order.
function Invoke-ReleaseTemplateLanguageChecks {

try {
    $routingStandard = Get-FileText -RelativePath "knowledge-hub/knowledge/standards/bilingual-public-private-routing.md"
    $assetRoutingStandard = Get-FileText -RelativePath "skills/project-bootstrap/assets/knowledge-hub-template/knowledge/standards/bilingual-public-private-routing.md"
    $catalogText = Get-FileText -RelativePath "knowledge-hub/knowledge-catalog.md"
    $assetCatalogText = Get-FileText -RelativePath "skills/project-bootstrap/assets/knowledge-hub-template/knowledge-catalog.md"
    $languagePolicy = Get-FileText -RelativePath "docs/language-policy.md"
    $readiness = Get-FileText -RelativePath "docs/release-readiness.md"
    $releaseProcess = Get-FileText -RelativePath "docs/release-process.md"

    $routingExpectations = [ordered]@{
        "knowledge-hub/knowledge/standards/bilingual-public-private-routing.md" = @("Maturity: verified", "Scope: cross-project", "User-facing conversation", "Public Boundary")
        "skills/project-bootstrap/assets/knowledge-hub-template/knowledge/standards/bilingual-public-private-routing.md" = @("Maturity: verified", "Scope: cross-project", "User-facing conversation", "Public Boundary")
        "knowledge-hub/knowledge-catalog.md" = @("Bilingual Public/Private Routing", "language routing")
        "skills/project-bootstrap/assets/knowledge-hub-template/knowledge-catalog.md" = @("Bilingual Public/Private Routing")
        "docs/language-policy.md" = @("Conversation And Artifact Routing", "Bilingual Public/Private Routing", "Simplified Chinese repository homepage", "-ProjectLanguage en", "-ProjectLanguage zh-CN", "未显式传入时")
        "docs/release-readiness.md" = @("Bilingual Public/Private Routing", "localized context discovery headings")
        "docs/release-process.md" = @("localized context discovery headings", "bilingual public/private routing")
    }

    $routingMissing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relativePath in $routingExpectations.Keys) {
        $text = switch ($relativePath) {
            "knowledge-hub/knowledge/standards/bilingual-public-private-routing.md" { $routingStandard }
            "skills/project-bootstrap/assets/knowledge-hub-template/knowledge/standards/bilingual-public-private-routing.md" { $assetRoutingStandard }
            "knowledge-hub/knowledge-catalog.md" { $catalogText }
            "skills/project-bootstrap/assets/knowledge-hub-template/knowledge-catalog.md" { $assetCatalogText }
            "docs/language-policy.md" { $languagePolicy }
            "docs/release-readiness.md" { $readiness }
            default { $releaseProcess }
        }
        foreach ($token in $routingExpectations[$relativePath]) {
            foreach ($missingToken in @(Get-MissingRequiredText -Text $text -RequiredText @($token))) {
                $routingMissing.Add("$relativePath missing token: $missingToken")
            }
        }
    }

    $script:evidence.routing = [ordered]@{
        checked_files = @($routingExpectations.Keys)
        missing = @($routingMissing.ToArray())
    }

    if ($routingMissing.Count -gt 0) {
        Add-Check "bilingual public/private routing" "FAIL" "Bilingual routing guidance is missing from public docs or bundled knowledge assets." $evidence.routing
    }
    else {
        Add-Check "bilingual public/private routing" "PASS" "Public/private language routing is documented in public-safe docs and bundled knowledge assets." $evidence.routing
    }
}
catch {
    Add-Check "bilingual public/private routing" "FAIL" $_.Exception.Message
}

}
