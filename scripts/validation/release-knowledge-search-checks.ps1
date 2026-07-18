# release-knowledge-search-checks.ps1
# Runtime-specific search, ranking, sorting, and parameter-binding compatibility checks.

function Invoke-ReleaseKnowledgeSearchChecks {
    try {
        $indexPath = Join-PathParts $repoRoot "knowledge-hub" "knowledge" "experience" "index.json"
        $index = Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json
        $searchScript = Join-PathParts $repoRoot "knowledge-hub" "scripts" "search_experience.ps1"
        $searchText = & $searchScript -HubDir (Join-PathParts $repoRoot "knowledge-hub") -Query "PowerShell command chaining" -Json
        $search = $searchText | ConvertFrom-Json
        $resultCount = @($search.results).Count
        if ($resultCount -lt 1) {
            throw "Experience search returned no matching entries."
        }
        $script:evidence.knowledge_hub = [ordered]@{
            index_path = $indexPath
            index_entries = @($index.entries).Count
            search_query = "PowerShell command chaining"
            search_results = $resultCount
            top_result = [string]$search.results[0].title
        }
        Add-Check "knowledge hub experience search" "PASS" "Experience index parsed and search returned public workflow experience." $evidence.knowledge_hub

        $searchIssueCloseout = (& $searchScript -HubDir (Join-PathParts $repoRoot "knowledge-hub") -Query "issue-closeout" -Json | ConvertFrom-Json)
        if (@($searchIssueCloseout.results).Count -lt 1 -or [string]$searchIssueCloseout.results[0].title -ne "Stacked PR Merge Incident Recovery") {
            throw "Experience search for 'issue-closeout' did not return the expected top result."
        }

        $searchForceWithLease = (& $searchScript -HubDir (Join-PathParts $repoRoot "knowledge-hub") -Query "force-with-lease" -Json | ConvertFrom-Json)
        if (@($searchForceWithLease.results).Count -lt 1 -or [string]$searchForceWithLease.results[0].title -ne "Stacked PR Merge Incident Recovery") {
            throw "Experience search for 'force-with-lease' did not return the expected top result."
        }

        $exactSearchCases = @(
            [ordered]@{ query = "parser error"; expected = "Windows PowerShell Command Chaining" },
            [ordered]@{ query = "command chaining"; expected = "Windows PowerShell Command Chaining" },
            [ordered]@{ query = "shell_command"; expected = "Windows PowerShell Command Chaining" },
            [ordered]@{ query = "stacked-pr"; expected = "Stacked PR Merge Incident Recovery" }
        )
        foreach ($case in $exactSearchCases) {
            $exactSearch = (& $searchScript -HubDir (Join-PathParts $repoRoot "knowledge-hub") -Query $case["query"] -Json | ConvertFrom-Json)
            if (@($exactSearch.results).Count -lt 1 -or [string]$exactSearch.results[0].title -ne [string]$case["expected"]) {
                throw ("Unexpected search result for '{0}'." -f $case["query"])
            }
        }

        $rankingCases = @(
            [ordered]@{
                query = "Unexpected token && in PowerShell"
                expected_titles = @("Windows PowerShell Command Chaining", "Stacked PR Merge Incident Recovery")
                expected_scores = @(10, 5)
            },
            [ordered]@{
                query = "command works in cmd but fails in PowerShell"
                expected_titles = @("Windows PowerShell Command Chaining", "Stacked PR Merge Incident Recovery")
                expected_scores = @(23, 10)
            }
        )
        foreach ($case in $rankingCases) {
            $rankedSearch = (& $searchScript -HubDir (Join-PathParts $repoRoot "knowledge-hub") -Query $case["query"] -MaxResults 2 -Json | ConvertFrom-Json)
            $rankedResults = @($rankedSearch.results)
            if ($rankedResults.Count -ne 2) {
                throw ("Expected two ranked results for '{0}', got {1}." -f $case["query"], $rankedResults.Count)
            }
            for ($i = 0; $i -lt 2; $i++) {
                if ([string]$rankedResults[$i].title -ne [string]$case["expected_titles"][$i] -or
                    [int]$rankedResults[$i].score -ne [int]$case["expected_scores"][$i]) {
                    throw ("Unexpected ranked result for '{0}' at position {1}." -f $case["query"], $i)
                }
            }
        }

        $maxOneSearch = (& $searchScript -HubDir (Join-PathParts $repoRoot "knowledge-hub") -Query "Unexpected token && in PowerShell" -MaxResults 1 -Json | ConvertFrom-Json)
        if (@($maxOneSearch.results).Count -ne 1 -or [string]$maxOneSearch.results[0].title -ne "Windows PowerShell Command Chaining") {
            throw "MaxResults=1 must keep the highest-scored experience result."
        }

        $mergedPrReopenSearch = (& $searchScript -HubDir (Join-PathParts $repoRoot "knowledge-hub") -Query "merged feature branch cannot be reopened" -Json | ConvertFrom-Json)
        if (@($mergedPrReopenSearch.results).Count -lt 1 -or [string]$mergedPrReopenSearch.results[0].title -ne "Stacked PR Merge Incident Recovery") {
            throw "Merged PR reopen symptom search must return the stacked PR recovery experience."
        }
    }
    catch {
        Add-Check "knowledge hub experience search" "FAIL" $_.Exception.Message
    }
}
