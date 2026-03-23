#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Post-processing script for the Halcyon Sentinel solution package.

.DESCRIPTION
    Run this after createSolutionV3.ps1 to promote the DCR and HalcyonEvents_CL table
    to top-level ARM resources so they update automatically on every solution upgrade
    via Content Hub, without requiring the user to re-click the "Deploy" button.

    The DCR and DCE are wrapped in a Microsoft.Resources/deployments nested deployment
    because ARM does not allow reference() in top-level resource names. The workspace
    customerId is passed as a parameter to the inner template so resources can be named
    to match what the Deploy button creates.

    The "Deploy" button remains necessary for first-time setup:
      - Entra app registration creation
      - Monitoring Metrics Publisher role assignment on the DCR
      - Push dataConnector resource creation (links Entra app + DCR)

.PARAMETER SolutionPath
    Path to the Halcyon solution directory. Defaults to the directory containing this script.

.PARAMETER SkipInfraDeployment
    Omit the DCE/DCR nested deployment (table is still promoted). Useful for testing
    whether the Deploy button is greyed out after a solution upgrade.

.EXAMPLE
    ./postprocess-package.ps1
    ./postprocess-package.ps1 -SolutionPath /path/to/Solutions/Halcyon
    ./postprocess-package.ps1 -SkipInfraDeployment
#>
param(
    [string]$SolutionPath = $PSScriptRoot,
    [switch]$SkipInfraDeployment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$mainTemplatePath  = Join-Path $SolutionPath "Package/mainTemplate.json"
$dcrSourcePath     = Join-Path $SolutionPath "Data Connectors/Halcyon_ccp/Halcyon_DCR.json"
$tableSourcePath   = Join-Path $SolutionPath "Data Connectors/Halcyon_ccp/Halcyon_table_events.json"

$template = Get-Content -Raw $mainTemplatePath | ConvertFrom-Json

# ── Build HalcyonInfrastructureDeployment (DCE + DCR) ───────────────────────
if (-not $SkipInfraDeployment) {
    $dcr = Get-Content -Raw $dcrSourcePath | ConvertFrom-Json

    # Adapt DCR for inner template parameter context
    $dcr.name     = "[concat('Microsoft-Sentinel-HalcyonDCR-', substring(parameters('workspaceCustomerId'), 0, 12))]"
    $dcr.location = "[parameters('workspaceLocation')]"
    $dcr.properties.dataCollectionEndpointId = "[resourceId('Microsoft.Insights/dataCollectionEndpoints', concat('ASI-', parameters('workspaceCustomerId')))]"
    $dcr.properties.destinations.logAnalytics | ForEach-Object {
        $_.workspaceResourceId = "[parameters('workspaceResourceId')]"
    }
    $dcr | Add-Member -NotePropertyName dependsOn -NotePropertyValue @(
        "[resourceId('Microsoft.Insights/dataCollectionEndpoints', concat('ASI-', parameters('workspaceCustomerId')))]"
    )

    $dce = [PSCustomObject]@{
        type       = "Microsoft.Insights/dataCollectionEndpoints"
        apiVersion = "2024-03-11"
        name       = "[concat('ASI-', parameters('workspaceCustomerId'))]"
        location   = "[parameters('workspaceLocation')]"
        properties = [PSCustomObject]@{}
    }

    $infraDeployment = [PSCustomObject]@{
        type       = "Microsoft.Resources/deployments"
        apiVersion = "2025-04-01"
        name       = "HalcyonInfrastructureDeployment"
        dependsOn  = @(
            "[resourceId('Microsoft.OperationalInsights/workspaces/tables', parameters('workspace'), 'HalcyonEvents_CL')]"
        )
        properties = [PSCustomObject]@{
            mode                        = "Incremental"
            expressionEvaluationOptions = [PSCustomObject]@{ scope = "inner" }
            parameters                  = [PSCustomObject]@{
                workspaceCustomerId = [PSCustomObject]@{ value = "[reference(resourceId('Microsoft.OperationalInsights/workspaces', parameters('workspace')), '2025-07-01').customerId]" }
                workspaceLocation   = [PSCustomObject]@{ value = "[parameters('workspace-location')]" }
                workspaceResourceId = [PSCustomObject]@{ value = "[resourceId('Microsoft.OperationalInsights/workspaces', parameters('workspace'))]" }
                subscription        = [PSCustomObject]@{ value = "[parameters('subscription')]" }
                resourceGroupName   = [PSCustomObject]@{ value = "[parameters('resourceGroupName')]" }
            }
            template = [PSCustomObject]@{
                '$schema'      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
                contentVersion = "1.0.0.0"
                parameters     = [PSCustomObject]@{
                    workspaceCustomerId = [PSCustomObject]@{ type = "string" }
                    workspaceLocation   = [PSCustomObject]@{ type = "string" }
                    workspaceResourceId = [PSCustomObject]@{ type = "string" }
                    subscription        = [PSCustomObject]@{ type = "string" }
                    resourceGroupName   = [PSCustomObject]@{ type = "string" }
                }
                resources = @($dce, $dcr)
            }
        }
    }

    $template.resources += $infraDeployment
}

# ── Promote HalcyonEvents_CL table to top level ──────────────────────────────
$table = Get-Content -Raw $tableSourcePath | ConvertFrom-Json
$table.name     = "[concat(parameters('workspace'), '/HalcyonEvents_CL')]"
$table.location = "[parameters('workspace-location')]"
$template.resources += $table

# ── Save mainTemplate.json and zip ───────────────────────────────────────────
$template | ConvertTo-Json -Depth 100 | Set-Content -Path $mainTemplatePath -Encoding UTF8

$zipPath = Get-ChildItem (Join-Path $SolutionPath "Package") -Filter "*.zip" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 -ExpandProperty FullName

if ($zipPath) {
    Compress-Archive -Path $mainTemplatePath -DestinationPath $zipPath -Update
}
