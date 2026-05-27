# Halcyon Alerts Sync

## Summary

This playbook runs on a recurrence schedule (default: every 1 minute) and manages the full lifecycle of Halcyon alerts in Microsoft Sentinel. Each run executes two phases in sequence:

**Alert ingestion** — queries `SecurityAlert` for new Halcyon-attributed alerts not yet recorded in the `HalcyonProcessedIds` watchlist, then creates a Sentinel incident for each one and adds the alert ID to the watchlist to prevent duplicates. Alerts whose triage status is already `Reviewed` or whose display status is `Hidden` are skipped at creation time.

**Incident sync** — queries open Halcyon incidents and reconciles each one against the latest alert state from `Halcyon_Commands_CL`: swaps the linked alert to the most recent one if it has changed, updates `Halcyon Triage Status:` and `Halcyon Display Status:` labels (skipping the PUT if labels are already current), closes the incident when triage status reaches `Reviewed`, and recovers orphaned incidents that lost their alert link.

The playbook authenticates to Azure Monitor Logs and Microsoft Sentinel using a system-assigned managed identity, and grants itself the necessary roles on the target workspace as part of deployment.

### Prerequisites

1. The Halcyon data connector must be deployed and ingesting data into the `Halcyon_Commands_CL` table.
2. The `HalcyonTriggersRule` analytics rule must be deployed with `createIncident: false` and entity mappings configured.
3. The deploying principal must have permission to create role assignments on the target Log Analytics workspace.

### Deployment Instructions

1. Click the Deploy to Azure button to launch the ARM Template deployment wizard.
2. Fill in the required parameters:
   * **PlaybookName**: Playbook name (default: `Halcyon-AlertsSync`).
   * **WorkspaceName**: Name of the Log Analytics workspace where Microsoft Sentinel and `Halcyon_Commands_CL` live.
   * **SubscriptionId**: Subscription containing the workspace (defaults to the deployment subscription).
   * **ResourceGroupName**: Resource group containing the workspace (defaults to the deployment resource group).
   * **WatchlistAlias**: Alias of the watchlist used to deduplicate processed alert IDs (default: `HalcyonProcessedIds`).
   * **RecurrenceInterval**: How often to run, in units of RecurrenceFrequency (default: `1`).
   * **RecurrenceFrequency**: `Minute` or `Hour` (default: `Minute`).

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2FAzure-Sentinel%2Fmaster%2FSolutions%2FHalcyon%2FPlaybooks%2FHalcyon-AlertsSync%2Fazuredeploy.json) [![Deploy to Azure Gov](https://aka.ms/deploytoazuregovbutton)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2FAzure-Sentinel%2Fmaster%2FSolutions%2FHalcyon%2FPlaybooks%2FHalcyon-AlertsSync%2Fazuredeploy.json)

### Post-Deployment Instructions

The ARM template wires up the Azure Monitor Logs and Microsoft Sentinel connections to use the playbook's system-assigned managed identity, creates the `HalcyonProcessedIds` watchlist, and creates the three role assignments listed below. No manual connection authorization or role assignment is required.

#### a. Roles assigned by the template

The playbook's managed identity is granted the following roles on the target Log Analytics workspace:

* **Microsoft Sentinel Contributor** — required to create and update incidents and manage the watchlist.
* **Log Analytics Reader** — required to run the scheduled KQL queries.
* **Monitoring Reader** — required by the Azure Monitor Logs connector at query time.

#### b. Verifying the first run

1. Go to Logic App → *your Logic App* → Run history.
2. Wait for the first scheduled run, or click **Run Trigger → Recurrence** to invoke immediately.
3. Confirm the run shows `Succeeded`. In the run details, check that `Run_AlertProcessor_KQL` returns the expected alerts and that any open Halcyon incidents processed by `Run_Update_KQL` show updated labels in the Sentinel portal.

If the first run fails with an authorization error, give the system-assigned identity a minute to propagate and re-run — Azure RBAC propagation can lag a few seconds behind deployment.
