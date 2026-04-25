---
description: Coordinate multiple agents for complex tasks. Use for multi-perspective analysis, comprehensive reviews, or tasks requiring different domain expertise.
---

# Multi-Agent Orchestration

You are now in **ORCHESTRATION MODE**. Your task: coordinate specialized agents to solve this complex problem.

## Task to Orchestrate
$ARGUMENTS

---

## 🔴 CRITICAL: Minimum Agent Requirement

> ⚠️ **ORCHESTRATION = MINIMUM 3 DIFFERENT AGENTS**
> 
> If you use fewer than 3 agents, you are NOT orchestrating - you're just delegating.
> 
> **Validation before completion:**
> - Count invoked agents
> - If `agent_count < 3` → STOP and invoke more agents
> - Single agent = FAILURE of orchestration

### Agent Selection Matrix

| Task Type | REQUIRED Agents (minimum) |
|-----------|---------------------------|
| **Web App** | frontend-specialist, backend-specialist, test-engineer |
| **API** | backend-specialist, security-auditor, test-engineer |
| **UI/Design** | frontend-specialist, seo-specialist, performance-optimizer |
| **Database** | database-architect, backend-specialist, security-auditor |
| **Full Stack** | project-planner, frontend-specialist, backend-specialist, devops-engineer |
| **Debug** | debugger, explorer-agent, test-engineer |
| **Security** | security-auditor, penetration-tester, devops-engineer |
| **Edge Functions (Supabase)** | backend-specialist, explorer-agent, debugger |

---

## Pre-Flight: Mode Check

| Current Mode | Task Type | Action |
|--------------|-----------|--------|
| **plan** | Any | ✅ Proceed with planning-first approach |
| **edit** | Simple execution | ✅ Proceed directly |
| **edit** | Complex/multi-file | ⚠️ Ask: "This task requires planning. Switch to plan mode?" |
| **ask** | Any | ⚠️ Ask: "Ready to orchestrate. Switch to edit or plan mode?" |

---

## 🔴 STRICT 2-PHASE ORCHESTRATION

### PHASE 1: PLANNING (Sequential - NO parallel agents)

| Step | Agent | Action |
|------|-------|--------|
| 1 | `project-planner` | Create docs/PLAN.md |
| 2 | (optional) `explorer-agent` | Codebase discovery if needed |

> 🔴 **NO OTHER AGENTS during planning!** Only project-planner and explorer-agent.

### ⏸️ CHECKPOINT: User Approval

```
After PLAN.md is complete, ASK:

"✅ Plan created: docs/PLAN.md

Do you approve? (Y/N)
- Y: Start implementation
- N: I'll revise the plan"
```

> 🔴 **DO NOT proceed to Phase 2 without explicit user approval!**

### PHASE 2: IMPLEMENTATION (Parallel agents after approval)

| Parallel Group | Agents |
|----------------|--------|
| Foundation | `database-architect`, `security-auditor` |
| Core | `backend-specialist`, `frontend-specialist` |
| Polish | `test-engineer`, `devops-engineer` |

> ✅ After user approval, invoke multiple agents in PARALLEL.

## Available Agents (6 total - Santa Flor CRM)

| Agent | Domain | Use When |
|-------|--------|----------|
| `frontend-specialist` | UI/UX | React, shadcn/ui, Vite |
| `backend-specialist` | Server | Supabase, Edge Functions, PostgreSQL |
| `database-architect` | Data | SQL, Schema, Migrations |
| `explorer-agent` | Discovery | Codebase mapping |
| `debugger` | Debug | Error analysis, troubleshooting |
| `code-archaeologist` | Refactor | Legacy code, improvements |

---

## Orchestration Protocol

### Step 1: Analyze Task Domains
Identify ALL domains this task touches:
```
□ Security     → security-auditor
□ Backend/API  → backend-specialist, explorer-agent
□ Frontend/UI  → frontend-specialist
□ Database     → database-architect
□ Testing      → test-engineer
□ DevOps       → devops-engineer
□ Edge Functions → backend-specialist, debugger
□ Freight/Label → backend-specialist, explorer-agent
```

### Step 2: Phase Detection

| If Plan Exists | Action |
|----------------|--------|
| NO `docs/PLAN.md` | → Go to PHASE 1 (planning only) |
| YES `docs/PLAN.md` + user approved | → Go to PHASE 2 (implementation) |

### Step 3: Execute Based on Phase

**PHASE 1 (Planning):**
```
Use the project-planner agent to create PLAN.md
→ STOP after plan is created
→ ASK user for approval
```

**PHASE 2 (Implementation - after approval):**
```
Invoke agents in PARALLEL:
Use the frontend-specialist agent to [task]
Use the backend-specialist agent to [task]
Use the explorer-agent agent to [task]
```

**🔴 CRITICAL: Context Passing (MANDATORY)**

When invoking ANY subagent, you MUST include:

1. **Original User Request:** Full text of what user asked
2. **Decisions Made:** All user answers to Socratic questions
3. **Previous Agent Work:** Summary of what previous agents did
4. **Current Plan State:** If plan files exist in workspace, include them

**Example with FULL context:**
```
Use the backend-specialist agent to work on Edge Function:

**CONTEXT:**
- User Request: "Debug gerar-etiqueta edge function that's failing"
- Decisions: Using SuperFrete API, endpoint is /gerar-etiqueta
- Previous Work: Explorer mapped the function files
- Current Plan: Function exists at supabase/functions/gerar-etiqueta

**TASK:** Debug and fix the edge function based on ABOVE context.
```

> ⚠️ **VIOLATION:** Invoking subagent without full context = subagent will make wrong assumptions!


### Step 4: Verification (MANDATORY)
The LAST agent must run appropriate verification scripts:
```bash
npm run lint
npm run build
```

### Step 5: Synthesize Results
Combine all agent outputs into unified report.

---

## Output Format

```markdown
## 🎼 Orchestration Report

### Task
[Original task summary]

### Mode
[Current Antigravity Agent mode: plan/edit/ask]

### Agents Invoked (MINIMUM 3)
| # | Agent | Focus Area | Status |
|---|-------|------------|--------|
| 1 | explorer-agent | Function discovery | ✅ |
| 2 | backend-specialist | Edge Function fix | ✅ |
| 3 | debugger | Error analysis | ✅ |

### Verification Scripts Executed
- [x] lint → Pass/Fail
- [x] build → Pass/Fail

### Key Findings
1. **[Agent 1]**: Finding
2. **[Agent 2]**: Finding
3. **[Agent 3]**: Finding

### Deliverables
- [ ] PLAN.md created
- [ ] Code implemented
- [ ] Functions verified

### Summary
[One paragraph synthesis of all agent work]
```

---

## 🔴 EXIT GATE

Before completing orchestration, verify:

1. ✅ **Agent Count:** `invoked_agents >= 3`
2. ✅ **Scripts Executed:** At least `lint` ran
3. ✅ **Report Generated:** Orchestration Report with all agents listed

> **If any check fails → DO NOT mark orchestration complete. Invoke more agents or run scripts.**

---

## Edge Functions Specific (Santa Flor CRM)

For freight/label tasks specifically:

| Task | Agents to Invoke |
|------|-----------------|
| Debug gerar-etiqueta | explorer-agent, backend-specialist, debugger |
| Debug cotar-frete | explorer-agent, backend-specialist |
| Add new shipping carrier | backend-specialist, database-architect |

**Begin orchestration now. Select 3+ agents, execute sequentially, run verification scripts, synthesize results.**