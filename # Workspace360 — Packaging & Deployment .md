# Workspace360 — Packaging & Deployment Guide

> **Status:** The unmanaged package has not been created yet.
> This document covers everything needed to create it, deploy it, configure the agent, and seed demo data.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [What Gets Packaged](#what-gets-packaged)
3. [Prerequisites](#prerequisites)
4. [Creating the Unmanaged Package](#creating-the-unmanaged-package)
5. [Installing the Package](#installing-the-package)
6. [Post-Install Setup](#post-install-setup)
7. [Seeding Demo Data](#seeding-demo-data)
8. [Configuring the Agentforce Agent](#configuring-the-agentforce-agent)
9. [Future State — Add Agent to Package](#future-state--add-agent-to-package)
10. [Troubleshooting](#troubleshooting)

---

## Project Structure

```
force-app/main/default/
  classes/                        ← All Apex classes + test classes
  lwc/                            ← Lightning Web Components
    workspace360Dashboard/        ← Main dashboard (both personas)
    workspace360GlobalTracker/    ← Background activity tracker
    workspace360SessionRestore/   ← Session restore component
    workspace360Tracker/          ← Tracker utility
  objects/
    User_Workspace_Context__c/    ← Session context per user
    W360_Incident_Log__c/         ← Org incident/error log
    NewObject__c/                 ← ⚠️  Demo test object — DO NOT package
  bots/
    Workspace360_Assistant/       ← Agent metadata (not packaged yet — see below)
manifest/
  package.xml                     ← Deployment manifest
```

---

## What Gets Packaged

### ✅ Included

| Type | Members |
|---|---|
| **Apex — Sales path** | `WorkspaceLogger`, `AgentforceSummary`, `W360GetLastSession`, `W360GetOpenOpportunities`, `W360GetOverdueTasks`, `W360GetPendingApprovals`, `W360GetWorkspaceSummary`, `W360GetDevActivitySummary`, `W360NavigateToDashboard`, `W360NavigateToRecord`, `W360OpenApexClass`, `Workspace360BackgroundTrackerController` |
| **Apex — Sysadmin path** | `W360AgentUtil`, `W360IncidentAnalyzer`, `W360GetRecentIncidents`, `W360GetIncidentDetails`, `W360AnalyzeAllIncidents` |
| **Apex — Test classes** | `AgentforceSummaryTest`, `W360GetDevActivitySummaryTest`, `W360OpenApexClassTest`, `WorkspaceLoggerTest`, `W360CoverageTest` |
| **LWC** | All 4 components above |
| **Custom Objects** | `User_Workspace_Context__c`, `W360_Incident_Log__c` |

### ❌ Excluded (intentionally)

| What | Why |
|---|---|
| `W360TestDataSeeder` | Demo-only — contains hardcoded user ID |
| `W360LiveDemoSeeder` | Demo-only — anchors to specific org audit trail |
| `Workspace360DemoSeeder` | Demo-only |
| `Workspace360IncidentSeeder` | Demo-only |
| `NewObject__c` | Test custom object, not production |
| Agentforce Agent / Topics | Not packageable yet — see [Future State](#future-state--add-agent-to-package) |

---

## Prerequisites

Before creating or installing the package, ensure the target org has:

- **Salesforce Edition:** Enterprise or above (Developer Edition for testing)
- **Agentforce enabled** — Setup → Einstein → Agentforce → Enable
- **API Version:** 63.0 or above
- **Salesforce CLI installed:** `sf --version` should return 2.x+
- **Dev Hub enabled** (for Unlocked Package path)
- **Test coverage ≥ 75%** — run all test classes before packaging

---

## Creating the Unmanaged Package

### Option A — Setup UI (quickest)

1. Go to **Setup → Package Manager → New**
2. Name: `Workspace360`
3. Type: **Unmanaged**
4. Click **Add → Add Components**
5. Add everything listed in the [What Gets Packaged](#what-gets-packaged) section above
6. Click **Upload**
7. Copy the install URL — looks like:
   `https://login.salesforce.com/packaging/installPackage.apx?p0=04t...`

### Option B — Salesforce CLI (recommended, repeatable)

```bash
# From inside the WorkspaceMarch28 folder

# 1. Ensure all tests pass first
sf apex run test --test-level RunLocalTests --wait 15 --target-org your-alias

# 2. Deploy using the package.xml manifest
sf project deploy start \
  --manifest manifest/package.xml \
  --target-org target-org-alias \
  --wait 10

# 3. Verify deployment
sf project deploy report --target-org target-org-alias
```

### Option C — Unlocked Package (best for long-term / upgradeable)

```bash
# One-time setup — create the package
sf package create \
  --name "Workspace360" \
  --package-type Unlocked \
  --path force-app \
  --target-dev-hub devhub-alias

# Create a version
sf package version create \
  --package "Workspace360" \
  --installation-key-bypass \
  --wait 20 \
  --target-dev-hub devhub-alias

# Promote to released
sf package version promote \
  --package "Workspace360@1.0.0-1" \
  --target-dev-hub devhub-alias

# Install in target org
sf package install \
  --package "Workspace360@1.0.0-1" \
  --target-org target-org-alias \
  --wait 10
```

---

## Installing the Package

### From Install URL (after Option A above)

1. Log in to the target org
2. Paste the install URL in the browser
3. Select **Install for All Users**
4. Click **Install**

### From CLI Deploy (after Option B above)

Already deployed — proceed to [Post-Install Setup](#post-install-setup).

---

## Post-Install Setup

After installing, complete these steps in the target org:

### 1. Assign the Lightning App Page

The `workspace360Dashboard` LWC needs to be added to a Lightning App Page or the navigation bar:

1. **Setup → Lightning App Builder → New**
2. Choose **App Page**
3. Name it `Workspace360Dashboard`
4. Add the `workspace360Dashboard` component to the page
5. **Activate** and assign to your Sales app (or all apps)

### 2. Add Global Tracker to Utility Bar

The background tracker needs to run on every page:

1. **Setup → App Manager** → find your Sales app → **Edit**
2. Go to **Utility Items**
3. Click **Add Utility Item → Custom Component**
4. Search for `workspace360GlobalTracker`
5. Set Panel Width: `340`, Panel Height: `480`
6. Check **Start automatically**
7. Save

### 3. Assign Permissions

Ensure users can access the custom objects:

1. **Setup → Permission Sets → New** (or use an existing one)
2. Add **Object Permissions** for:
   - `User_Workspace_Context__c` — Read, Create, Edit, Delete
   - `W360_Incident_Log__c` — Read, Create, Edit, Delete (admins only)
3. Add **Apex Class Access** for all `W360*` and `Workspace360*` classes
4. Assign the permission set to relevant users

---

## Seeding Demo Data

> These classes are **not in the package** — they must be run manually in the target org after deploying from source. Deploy the full source (not just the package) to a scratch or developer org for demo purposes.

### Sales / Session Demo Data

Seeds realistic Opportunities, Leads, and session context records across 1D / 7D / 30D windows for a specific user.

**Step 1 — Update the hardcoded user ID**

Open `W360TestDataSeeder.cls` and replace the user ID on line 4:

```apex
// Replace this with the actual user ID in your org
Id uid = '005aj00000Tci0y';  // ← change this
```

To find the right ID:
```apex
// Run in Developer Console → Execute Anonymous
System.debug(UserInfo.getUserId());
```

**Step 2 — Run the seeder**

In Developer Console → Execute Anonymous:
```apex
W360TestDataSeeder.seed();
```

This creates:
- 3 Leads (Jordan Lee, Maria Santos, Kevin Oduya)
- 3 Opportunities (TechFit Enterprise Expansion, Blue Ridge Q2 Renewal, NovaBridge Platform Deal)
- 13 session context records spread across today / yesterday / 3 days ago / 5 days ago / 12 days ago / 20 days ago / 26 days ago
- Shows **5 records** in 1D view, **9 records** in 7D view, **13 records** in 30D view

### Incident / Sysadmin Demo Data

Seeds `W360_Incident_Log__c` records spread across time so the 1D / 7D / 30D incident filters show meaningfully different data.

**Basic incident seed (no correlation needed):**
```apex
Workspace360IncidentSeeder.seedAll();
```

This creates 6 incidents:
- **Today (1D):** OpportunityTriggerHandler (SOQL limit), Lead_Conversion_Flow (validation)
- **5 days ago (7D):** AccountSyncBatch (null pointer), CasePriorityFlow (CPU limit)
- **15 days ago (30D):** NightlyReportBatch (aborted), ContactDuplicateCheck (DML exception)

**Live demo seed (correlates with real SetupAuditTrail changes):**
```apex
// Seeds incidents timed around your actual recent deployments
// so the change correlation feature shows real results
W360LiveDemoSeeder.seed();
```

**Clean up all demo data:**
```apex
Workspace360IncidentSeeder.deleteAll();
W360LiveDemoSeeder.cleanUp();
delete [SELECT Id FROM User_Workspace_Context__c];
```

### NewObject__c Demo Records

`NewObject__c` is a placeholder custom object used to demonstrate that Workspace360 tracks activity across **any** Salesforce object — not just standard ones. It ships with the source but is excluded from the package.

To create demo records manually in a scratch/dev org:
```apex
insert new List<NewObject__c>{
    new NewObject__c(Name = 'Custom Record Alpha'),
    new NewObject__c(Name = 'Custom Record Beta'),
    new NewObject__c(Name = 'Custom Record Gamma')
};
```

> In production use, `NewObject__c` should be replaced with whatever real custom objects exist in the target org. The `workspace360GlobalTracker` LWC tracks any object automatically — no code changes needed.

---

## Configuring the Agentforce Agent

> The agent is **not included in the package**. After installing, the target org admin must create the agent manually. All 12 actions will already be available because the `@InvocableMethod` Apex classes are installed.

### Step 1 — Create the Agent

1. **Setup → Agents → New Agent**
2. Template: **Agentforce Employee Agent** (same as source org)
3. Name: `Workspace360 Assistant`
4. Description:
   > Workspace360 Assistant helps Salesforce users stay productive by summarizing their recent CRM activity, restoring previous work sessions, and surfacing what needs attention — overdue tasks, open deals, and pending approvals — all from one place.

### Step 2 — Create Topic: Workspace Assistant (Sales)

1. In the agent builder, click **New Topic**
2. **Topic Name:** `Workspace Assistant`
3. **Classification Description:**
   > Use this topic when the user asks about their recent Salesforce activity, what records they worked on, what they were doing recently, their open opportunities, overdue tasks, pending approvals, or when they want to restore or resume their last session.
4. **Instructions:**
   > You are a personal productivity assistant for Salesforce users. You have access to the user's recent record activity, session history, open opportunities, overdue tasks, and pending approvals. Always greet the user by summarizing what you found. After each response, suggest 2-3 relevant follow-up actions. Never ask the user to navigate somewhere themselves — use the navigation actions to open records and pages directly.

5. **Add Actions** — select all of these (they will appear in the list):
   - `Get Workspace Summary`
   - `Get Last Session`
   - `Get Open Opportunities`
   - `Get Overdue Tasks`
   - `Get Pending Approvals`
   - `Get Dev Activity Summary`
   - `Navigate to Workspace360 Dashboard`
   - `Navigate to Workspace360 Record`
   - `Open Apex Class`

### Step 3 — Create Topic: Org Health Assistant (Sysadmin)

1. Click **New Topic**
2. **Topic Name:** `Org Health Assistant`
3. **Classification Description:**
   > Use this topic when the user asks about production errors, what broke, recent incidents, failing Apex jobs, batch failures, org health, what changed before an error, or root cause analysis of any Salesforce exception.
4. **Instructions:**
   > You are a Salesforce org health expert. You have access to real production error data from AsyncApexJob failures and ApexLog exceptions. When the user asks about errors, always fetch incidents first, then offer to investigate each one in detail. Present incidents in a numbered list. After investigating one incident, proactively offer to investigate the next. Always include root cause analysis and a recommended fix. Correlate errors with recent metadata changes when available.

5. **Add Actions** — select:
   - `W360: Get Recent Production Incidents`
   - `W360: Get Incident Details with Dev Changes`
   - `W360: Production Health Report`

### Step 4 — Activate the Agent

1. Click **Activate** in the agent builder
2. Go to **Setup → Embedded Service Deployments** (or the Lightning App utility bar)
3. Add the agent to the Workspace360 utility bar component

---

## Future State — Add Agent to Package

Once Salesforce stabilises `GenAiPlannerBundle` and `GenAiFunctionDef` metadata packaging support (expected API 64.0+), add these steps:

### 1. Retrieve Agent Metadata from Source Org

```bash
# Check exact API names first
sf org list metadata --metadata-type Bot --target-org your-alias
sf org list metadata --metadata-type BotVersion --target-org your-alias
sf org list metadata --metadata-type GenAiPlannerBundle --target-org your-alias
sf org list metadata --metadata-type GenAiFunctionDef --target-org your-alias

# Then retrieve
sf project retrieve start \
  --metadata "Bot:Workspace360_Assistant" \
  --metadata "BotVersion:Workspace360_Assistant.v1" \
  --metadata "GenAiPlannerBundle:Workspace360_Assistant" \
  --metadata "GenAiFunctionDef" \
  --target-org your-alias
```

### 2. Verify Files Exist

```bash
find force-app -name "*.bot-meta.xml" \
  -o -name "*.botVersion-meta.xml" \
  -o -name "*.genAiPlannerBundle-meta.xml" \
  -o -name "*.genAiFunctionDef-meta.xml"
```

### 3. Add to package.xml

```xml
<types>
    <members>Workspace360_Assistant</members>
    <n>Bot</n>
</types>

<types>
    <members>Workspace360_Assistant.v1</members>
    <n>BotVersion</n>
</types>

<types>
    <members>*</members>
    <n>GenAiPlannerBundle</n>
</types>

<types>
    <members>*</members>
    <n>GenAiFunctionDef</n>
</types>
```

### 4. Switch to Unlocked Package

Unmanaged packages do not support `GenAiPlannerBundle`. Switch to Unlocked:

```bash
sf package create \
  --name "Workspace360" \
  --package-type Unlocked \
  --path force-app \
  --target-dev-hub devhub-alias
```

---

## Troubleshooting

**"Insufficient Privileges" on custom object after install**
→ Assign the permission set to the user. See [Post-Install Setup → Assign Permissions](#3-assign-permissions).

**Dashboard shows no activity**
→ The global tracker needs to be added to the utility bar and set to start automatically. See [Post-Install Setup → Add Global Tracker](#2-add-global-tracker-to-utility-bar).

**Agent actions don't appear in agent builder**
→ Ensure the `@InvocableMethod` Apex classes are deployed. Run:
```bash
sf apex list class --target-org your-alias | grep W360
```

**Test coverage below 75%**
→ Deploy `W360CoverageTest.cls` first, then run:
```bash
sf apex run test --test-level RunLocalTests --wait 15 --target-org your-alias
```

**`W360TestDataSeeder` fails with "invalid id"**
→ Update the hardcoded user ID on line 4. See [Seeding Demo Data → Sales Demo Data](#sales--session-demo-data).

**Incidents not showing in dashboard**
→ Run `Workspace360IncidentSeeder.seedAll()` in Execute Anonymous to populate demo data.

---

*Workspace360 — Salesforce Partner Innovation Challenge 2026*
