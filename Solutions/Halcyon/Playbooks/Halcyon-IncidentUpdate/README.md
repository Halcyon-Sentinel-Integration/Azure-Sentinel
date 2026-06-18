# Halcyon Incident Update

## Summary

This playbook is triggered on a recurrence schedule (default: every 5 minutes) and keeps open Halcyon Sentinel incidents in sync with the latest Halcyon alert state. It runs a KQL query that joins `SecurityIncident`, `SecurityAlert`, and the Halcyon `Halcyon_Commands_CL` custom table to find open incidents whose alerts have a newer triage or display status, then iterates each match and updates the incident via the Microsoft Sentinel connector — replacing any existing `Halcyon Triage Status:` and `Halcyon Display Status:` labels with the current values. The playbook authenticates to Azure Monitor Logs and Microsoft Sentinel using a system-assigned managed identity, and grants itself Sentinel Responder, Log Analytics Reader, and Monitoring Reader on the target workspace as part of deployment.

### Prerequisites

1. The Halcyon data connector must be deployed and ingesting data into the `Halcyon_Commands_CL` table.
2. The `HalcyonTriggersRule` analytics rule and its companion automation rule must be deployed (these create the incidents this playbook keeps in sync).
3. The deploying principal must have permission to create role assignments on the target Log Analytics workspace.

### Deployment Instructions

1. To deploy the Playbook, click the Deploy to Azure button. This will launch the ARM Template deployment wizard.
2. Fill in the required parameters:
   * PlaybookName: Enter the playbook name here (default: Halcyon-IncidentUpdate).
   * WorkspaceName: Name of the Log Analytics workspace where Microsoft Sentinel and `Halcyon_Commands_CL` live.
   * SubscriptionId: Subscription containing the workspace (defaults to the deployment subscription).
   * ResourceGroupName: Resource group containing the workspace (defaults to the deployment resource group).
   * RecurrenceInterval: How often to run the sync, in units of RecurrenceFrequency (default: 5).
   * RecurrenceFrequency: `Minute` or `Hour` (default: Minute).

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2FAzure-Sentinel%2Fmaster%2FSolutions%2FHalcyon%2FPlaybooks%2FHalcyon-IncidentUpdate%2Fazuredeploy.json) [![Deploy to Azure Gov](https://aka.ms/deploytoazuregovbutton)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2FAzure-Sentinel%2Fmaster%2FSolutions%2FHalcyon%2FPlaybooks%2FHalcyon-IncidentUpdate%2Fazuredeploy.json)

### Post-Deployment Instructions

The ARM template wires up the Azure Monitor Logs and Microsoft Sentinel connections to use the playbook's system-assigned managed identity, and creates the three role assignments listed below. No manual connection authorization or role assignment is required.

#### a. Roles assigned by the template

The playbook's managed identity is granted the following roles on the target Log Analytics workspace:

* Microsoft Sentinel Responder — required to update incident labels.
* Log Analytics Reader — required to run the scheduled KQL query.
* Monitoring Reader — required by the Azure Monitor Logs connector at query time.

#### b. Verifying the first run

1. Go to Logic App → *your Logic App* → Run history.
2. Wait for the first scheduled run, or click **Run Trigger → Recurrence** to invoke immediately.
3. Confirm the run shows `Succeeded` and that any incidents listed in the `Run_KQL_Query` output were updated with the current `Halcyon Triage Status:` and `Halcyon Display Status:` labels.

If the first run fails with an authorization error, give the system-assigned identity a minute to propagate and re-run — Azure RBAC propagation can lag a few seconds behind deployment.
