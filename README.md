# Workspace 360 — AI-Powered Personal Assistant for Salesforce

> **Agentforce Hackathon 2026** · Built natively on Salesforce + Agentforce · No external tools required

Workspace 360 is a Lightning Web Component panel embedded inside Salesforce that adapts to who is logged in. **Sales engineers** get instant session context and next-step recommendations. **System administrators** get real-time org health monitoring with AI-powered incident triage. Both interact through the same Agentforce-powered chat interface.

---

## The Problem

Salesforce users constantly lose their working context.

- A **sales engineer** logs back in with no immediate sense of what they were working on, what's most urgent, or whether approvals are pending. They manually scroll through Recently Viewed trying to reconstruct their session.
- A **system administrator** sees something break and has to cross-reference Jira tickets with Salesforce error logs manually, with no technical detail about what actually failed or why.

Neither persona has an intelligent layer that says: *"here's where you left off, here's what matters most, and here's what's broken."*

---

## The Solution

### For Sales Engineers — Resume Session

`workspace360GlobalTracker` lives in the Salesforce utility bar and silently tracks every record the user visits (URL polling every 1.2s, any object type, zero configuration). On next login:

- A **Restore Session banner** shows the last N records as cards with Name, Object, Stage, and Amount
- The **Agentforce agent** generates a personalized AI summary: *"You were working on Acme Corp Opportunity — Proposal stage, last edited 3 hours ago"*
- One click on any card calls `W360NavigateToRecord` and the SE is back in context instantly — like Chrome tab restore, inside Salesforce

**Tech stack:**
```
window.location.href polling (1.2s)
  → workspace360GlobalTracker LWC (utility bar)
  → WorkspaceLogger.logActivity() [@AuraEnabled Apex]
  → User_Workspace_Context__c [custom object, upsert deduped by user+record+day]
  → markSessionEnd() on beforeunload / visibilitychange
  
Next login:
  W360GetLastSession [@InvocableMethod]
  → WorkspaceLogger.getLastSession()
  → User_Workspace_Context__c [ORDER BY Session_Timestamp__c DESC]
  → Restore Session banner + Agentforce AI summary
  → W360NavigateToRecord [@InvocableMethod] on click
```

### For System Administrators — Incident Triage

Workspace 360 monitors org health from three native Salesforce sources simultaneously, with no org setup required:

| Source | What it captures |
|--------|-----------------|
| `AsyncApexJob` | Every failed batch, queueable, scheduled, and future job — with full `ExtendedStatus` exception message |
| `W360_Incident_Log__c` | Normalized incident store fed by the Error Log Adapter (see below) |
| `ApexLog` | Failed debug log entries flagged with non-Success status |

When the admin asks **"What broke today?"**, the Agentforce agent calls `W360GetRecentIncidents`, which queries all three sources, deduplicates by Apex class, classifies severity, and returns a ranked incident list in plain English.

When the admin asks **"Why is OpportunityTriggerHandler failing?"**, the agent calls `W360GetIncidentDetails`, which:
1. Finds the most recent matching error
2. Queries `SetupAuditTrail` for dev changes in the **120 minutes before** the error timestamp
3. Applies relevance scoring — changes are ranked by how closely the component name matches the failing class, and filtered by error type (a `LimitException` cannot be caused by a Validation Rule — those are skipped automatically)
4. Runs AI root-cause analysis combining the error message, stack trace, and correlated changes
5. Returns a plain-English explanation with a concrete fix recommendation

---

## The Error Log Adapter

The standout architectural feature: **Workspace 360 can read from any existing error log object in any org — with zero code changes.**

Configuration is done entirely through `W360_Error_Source__mdt` Custom Metadata:

| Field | Purpose |
|-------|---------|
| `Source_Object_API_Name__c` | The org's existing error log object (e.g. `Error_Log__c`) |
| `Error_Message_Field__c` | Their message field |
| `Timestamp_Field__c` | Their timestamp field (defaults to `CreatedDate`) |
| `Severity_Field__c` | Optional — their severity/log level field |
| `Class_Name_Field__c` | Optional — Apex class name field |
| `Stack_Trace_Field__c` | Optional — stack trace field |
| `Lookback_Hours__c` | How far back to query (default 24) |
| `Min_Severity__c` | Minimum severity to sync (default Warning) |
| `Is_Active__c` | Toggle without deleting the config |

`W360ErrorLogAdapter` runs hourly via `W360ErrorLogAdapterScheduler`, builds a dynamic SOQL query from the config, normalizes severity values (`ERROR/FATAL/P1` → Critical, `WARN/P2` → Warning, `INFO/DEBUG` → Info), and upserts into `W360_Incident_Log__c` using `Source_Record_Id__c` as the external ID — so no duplicate incidents are ever created across sync runs.

**For a new org:** create one metadata record pointing to their error log object → run the schedule command once → done. No deployment, no code changes.

---

## Why Agentforce

A static dashboard cannot solve this problem — because the problem is not a lack of data, it is a lack of reasoning.

- For a sales engineer, the agent needs to query recent activity, infer urgency from deadlines and approvals, and surface a personalized recommendation — not just display a list.
- For a sysadmin, the agent needs to query `AsyncApexJob` for failures, cross-reference `ApexLog` for runtime exceptions, look up `SetupAuditTrail` for correlated metadata changes, classify severity, and return a structured root cause analysis — all in response to a single natural language prompt.

No dashboard, report, or standard chatbot can chain these steps autonomously. Agentforce makes this possible natively inside Salesforce with no external tools or integrations required.

---

## Agentforce Actions

| Action | Trigger phrases | What it does |
|--------|----------------|--------------|
| `W360GetRecentIncidents` | "What broke today?", "Any errors in the last 24 hours?" | Queries all error sources, deduplicates, ranks by severity |
| `W360GetIncidentDetails` | "Why is X failing?", "What changed before the error?" | Root cause analysis + SetupAuditTrail correlation |
| `W360AnalyzeAllIncidents` | "Give me a production health report" | Full standup-style digest across all incidents |
| `W360GetLastSession` | "What was I working on?", "Resume my session" | Returns last session records with timestamps |
| `W360GetWorkspaceSummary` | "Summarize my workspace" | AI summary of recent activity across object types |
| `W360GetOpenOpportunities` | "Show my pipeline" | Open opportunities with stage and amount |
| `W360GetOverdueTasks` | "What's overdue?" | Overdue tasks ranked by priority |
| `W360GetPendingApprovals` | "Any approvals waiting on me?" | Pending approval requests for the current user |
| `W360NavigateToRecord` | "Take me to Acme Corp" | Navigates the user to a specific record |
| `W360OpenApexClass` | "Open OpportunityTriggerHandler" | Opens Apex class in Setup for sysadmin |

---

## Data Model

```
User_Workspace_Context__c     ← session tracking (SE persona)
  User__c                     Lookup(User)
  Record_Id__c                Text — the visited record
  Object_Type__c              Text — Opportunity, Case, etc.
  Session_Timestamp__c        DateTime — last visit time
  Is_Active_Session__c        Checkbox — cleared on tab close
  Stage__c, Amount__c         Denormalized for fast card rendering

W360_Incident_Log__c          ← normalized incident store (Sysadmin persona)
  Apex_Class__c               Text — failing class or job name
  Error_Message__c            LongText
  Exception_Type__c           Text — System.LimitException, etc.
  Severity__c                 Picklist — Critical / Warning / Info
  Occurred_At__c              DateTime
  Stack_Trace__c              LongText
  Source_Record_Id__c         Text (External ID, Unique) — dedup key
  Triggered_By__c             Text — sync source label

W360_Error_Source__mdt        ← adapter config (one record per error log table)
  Source_Object_API_Name__c   Text — the org's error log SObject
  Error_Message_Field__c      Text — field mapping
  Severity_Field__c           Text — field mapping
  Lookback_Hours__c           Number
  Min_Severity__c             Text
  Is_Active__c                Checkbox
```

---

## Setup

### Prerequisites
- Salesforce org with Agentforce enabled
- SF CLI installed

### Deploy

```bash
# 1. Authenticate
sf org login web --alias w360

# 2. Deploy everything
sf project deploy start --manifest manifest/package.xml --target-org w360

# 3. Schedule the hourly error log sync
sf apex run --file scripts/apex/scheduleAdapter.apex --target-org w360

# 4. Seed demo data and run first sync (for demo/judging)
sf apex run --file scripts/apex/seedAndSync.apex --target-org w360
```

### For a new org's error log

Go to **Setup → Custom Metadata Types → W360 Error Source → Manage Records → New** and fill in:
- Label: any name
- Source Object API Name: their object (e.g. `Error_Log__c`)
- Error Message Field: their message field (e.g. `Message__c`)
- Is Active: checked

That's it. The adapter handles the rest on the next hourly run.

### Scheduled jobs

| Job | Schedule | Purpose |
|-----|----------|---------|
| W360 Error Log Sync | Every hour | Syncs org error log → W360_Incident_Log__c |
| W360 Data Purge | Every Sunday 2am | Deletes context > 30 days, incidents > 90 days |

---

## Project Structure

```
force-app/main/default/
├── classes/
│   ├── W360ErrorLogAdapter.cls          # Core adapter — reads any error log object
│   ├── W360ErrorLogAdapterScheduler.cls # Hourly scheduler
│   ├── W360IncidentAnalyzer.cls         # Incident query + SetupAuditTrail correlation + AI analysis
│   ├── W360AgentUtil.cls                # Shared DTOs and helpers
│   ├── W360GetRecentIncidents.cls       # Agentforce: "What broke today?"
│   ├── W360GetIncidentDetails.cls       # Agentforce: root cause analysis
│   ├── W360AnalyzeAllIncidents.cls      # Agentforce: full health report
│   ├── W360GetLastSession.cls           # Agentforce: session restore
│   ├── W360GetWorkspaceSummary.cls      # Agentforce: workspace summary
│   ├── W360GetOpenOpportunities.cls     # Agentforce: pipeline
│   ├── W360GetOverdueTasks.cls          # Agentforce: overdue tasks
│   ├── W360GetPendingApprovals.cls      # Agentforce: approvals
│   ├── W360NavigateToRecord.cls         # Agentforce: navigation
│   ├── W360OpenApexClass.cls            # Agentforce: open class in Setup
│   ├── W360DataPurgeScheduler.cls       # Weekly data cleanup
│   ├── W360DemoErrorLogSeeder.cls       # Seeds Demo_Error_Log__c for demos
│   └── WorkspaceLogger.cls             # Session tracking core
├── objects/
│   ├── User_Workspace_Context__c/       # SE session store
│   ├── W360_Incident_Log__c/            # Sysadmin incident store
│   ├── W360_Error_Source__mdt/          # Adapter config metadata type
│   └── Demo_Error_Log__c/              # Demo error log object
├── customMetadata/
│   └── W360_Error_Source.Demo_Org_Error_Log.md-meta.xml  # Pre-wired demo config
├── lwc/
│   ├── workspace360Dashboard/           # Main panel (persona-aware)
│   ├── workspace360GlobalTracker/       # Utility bar session tracker
│   ├── workspace360SessionRestore/      # Restore session banner
│   └── workspace360Tracker/            # Per-record activity tracking
└── bots/
    └── Workspace360_Assistant/          # Agentforce bot definition
```
W360ErrorLogAdapterScheduler 
W360 Data Purge

---

## Demo Credentials (for judges)

https://docs.google.com/document/d/1cJwT86LFeGt4o6l9O853DXNaHLKPZci2jGyYQJ7RAGI/edit?tab=t.0
https://docs.google.com/document/d/1QW8LFZfoWYt0RPe51qjXAlpu_J0WcaaFStgX4F5TdI4/edit?tab=t.0
https://docs.google.com/presentation/d/1LOI7uTercmUWa7HbTQk6Eec8-hbERD24/edit?slide=id.g3d34e54cf4d_0_37#slide=id.g3d34e54cf4d_0_37



---

## Team

Built for the **Agentforce Hackathon 2026** — one assistant, two personas, zero context lost.
