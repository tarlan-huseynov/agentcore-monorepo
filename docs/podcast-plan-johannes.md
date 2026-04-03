# Podcast Episode Plan — Johannes Koch x Tarlan

**Channel:** [Lockhead Cloud](https://www.youtube.com/@lockheadcloud)
**Format:** Conversation / podcast-style, 20-40 min
**Target audience:** Cloud practitioners — DevOps, platform engineers, teams shipping to AWS

---

## Episode Title

**"There's No Playbook Yet: Shipping AI Agents to Production"**

**One-line hook:** We have standards for everything in cloud — except agents. Here's what happens when you try to apply them anyway.

---

## Section 1 — The Established World (~5 min)

**Goal:** Establish Tarlan's credibility through breadth of experience, then set the baseline so the contrast lands hard when agents enter the picture.

**Johannes opens:**
- Introduces Tarlan, his background, what brought him to this topic
- "Before we get into agents — tell us a bit about your background. What have you been shipping and where?"

**Tarlan's talking points:**
- Across tens of projects, touched essentially every deployment type that exists: bare metal, VMs, containers on ECS and Kubernetes, serverless Lambda, Step Functions for orchestration, fully managed PaaS, hybrid stacks
- Different industries, different team sizes, different scales — but the patterns converge
- Over time you develop a mental model: here's the problem, here's the right primitive, here's how you wire the SDLC around it
- Containers → ECS or Kubernetes. Event-driven → Lambda. Orchestration → Step Functions. IaC with Terraform or CDK. GitOps for delivery. Commit → CI → artifact → staging → prod. It becomes muscle memory.
- The path is defined. You still make decisions, but the decision tree is known.

**Johannes follow-up:** "So across all those projects — did you ever hit something where the playbook just didn't apply?"

**Tarlan:** "Yeah. Agents."

**Transition:** "Then agents showed up — and none of that mapped."

---

## Section 2 — What Agents Break (~8 min)

**Goal:** Surface the genuine problem. Make it concrete, not abstract.

**Johannes prompts:** "What's actually different about deploying an AI agent vs. a normal service?"

**Tarlan's talking points:**
- A service is deterministic. You call it, it returns. You test it, you ship it.
- An agent is a loop. It decides what to do next, calls tools, accumulates state, reasons across steps. Non-deterministic by design.
- The unit of deployment is no longer one thing — it's a constellation: the agent runtime, MCP tool servers, a gateway to route between them, a memory store for session persistence, a policy engine for safety guardrails, IAM roles for each, log groups for observability. All of these need to exist and be wired correctly.
- Platform choice is genuinely unresolved. Lambda? Cold starts hurt long agentic loops. ECS? Now you're managing containers and scaling for something that runs in bursts. Kubernetes? Serious overhead for what might be a single-tenant workload. Managed runtime? You're betting on a young service with gaps in tooling.

**Host follow-up questions:**
- "How are teams actually making this call right now?"
- "Is there a wrong answer, or is it all contextual?"

**Tarlan:** Nobody has a standard. Every team is improvising. That's the honest situation. We're paving the road as we drive.

**Transition:** "So I decided to just pick one and document everything — including the ugly parts."

---

## Section 3 — AgentCore as Serverless for Agents + Why Terraform Wins (~12 min)

**Goal:** The concrete example. This is the meat of the episode.

### 3a. Why AgentCore

**Johannes:** "You picked AgentCore. Why that over ECS or Lambda?"

**Tarlan's talking points:**
- AgentCore's pitch is essentially serverless for agents: you bring the code, AWS handles compute, scaling, auth, networking. No containers to babysit, no cluster to manage.
- This is compelling when your application is actually 3 coordinated runtimes — the main agent, a Cloud Control API MCP server, a Cost Explorer MCP server — plus a gateway routing between them, plus memory, plus Cedar policy enforcement. That's a lot of managed surface area.
- AgentCore absorbs the operational burden of all of it. That's the hybrid play: managed primitives, your code.

**Host follow-up:** "What's the catch with managed? What do you give up?"

**Tarlan:** Tooling maturity. The service is new. You hit edges fast.

---

### 3b. The Starter Kit Gap

**Johannes:** "AWS ships a starter kit. Why wasn't that enough?"

**Tarlan's talking points:**
- The starter kit and CLI v3 get you running. Good for a demo.
- But it's imperative — you run commands, things get created, and there's no declarative record of what exists. No version history. No way to reproduce it exactly on a new account. No diff to review in a PR.
- The moment you're on a team, or you want to iterate, or something breaks and you need to know what changed — you're lost.

**Host follow-up:** "So what's the actual problem — the tooling or the mindset?"

**Tarlan:** Both. The mindset in AI tooling is still "get it working." The infrastructure mindset is "define it, version it, automate it." Those two haven't merged yet.

---

### 3c. The Key Insight — It's Not Just Code Anymore

**Tarlan's core talking point:**
- An AgentCore application is not just a code deployment. It's a code deployment *plus* a full configuration of managed systems that all have to be in sync: runtime configs, gateway targets, Cedar policy engine, memory strategy, IAM roles per runtime, CloudWatch log groups, S3 for deployment artifacts.
- If any of these drift independently, the agent breaks in subtle and hard-to-diagnose ways. The gateway can't route because the target config is stale. The policy engine strips tools that haven't been registered. Memory fails because the session ID format doesn't match.
- You need everything captured in one place, versioned together.

**Host follow-up:** "That's a different problem than 'deploy my Lambda.' How do you even structure that?"

---

### 3d. Why Terraform

**Tarlan's talking points:**
- One monorepo: application code + MCP server code + all Terraform in the same repo, same commit, same PR.
- `terraform apply` builds the packages, uploads to S3, deploys all three runtimes, wires the gateway, sets IAM, configures memory. One command, full stack.
- Everything is versioned, reviewable in a diff, auditable. This is the IaC value proposition applied to agents.
- Code version trick: Terraform hashes the source, injects the hash as an env var, forcing AgentCore to re-fetch from S3 on every code change. Solves the "changed code but nothing redeployed" problem.

**Host follow-up:** "What were the workarounds? Where did Terraform fall short?"

**Tarlan's caveats:**
- Gateway targets can't be managed by the provider — missing `grantType` support. Workaround: CLI script wrapped in a `null_resource`.
- Cedar policy engine has no Terraform resource at all. Another `null_resource` + AWS CLI.
- The provider can't read back certain fields after apply, so Terraform sees drift on every plan. Workaround: `ignore_changes` on those fields.
- These aren't blockers — but you'd never know they exist until you hit them. Documenting them saves the next person hours.

**Transition:** "So we have a working approach. But is it *the* approach?"

---

## Section 4 — Open Questions (~8 min)

**Goal:** Zoom out. Make it a conversation about where this all goes.

**Johannes leads:**

**Q1:** "Is Terraform the right long-term answer for agents, or are we forcing a square peg?"
- Tarlan: Honest answer — maybe not forever. But right now it's the most mature IaC tool that can express both code and config. CDK is a contender. Purpose-built agent deployment tooling doesn't exist yet.

**Q2:** "How do you test a non-deterministic agent in a CI pipeline?"
- Tarlan: This is the genuinely unsolved problem. Unit tests on pure helpers work. Integration tests on tool behavior work. But end-to-end agent behavior testing — evaluating whether the agent *reasoned* correctly — that's a different discipline. AgentCore Evaluations is one answer, but the field is early.

**Q3:** "Will managed runtimes like AgentCore become the ECS of the agent era?"
- Tarlan: That's the bet. The analogy holds — ECS abstracted away container orchestration, AgentCore abstracts away agent runtime orchestration. The question is adoption speed and tooling maturity.

**Q4:** "What does a mature agent SDLC look like in 2-3 years?"
- Tarlan: Commit triggers a pipeline. Pipeline runs agent evaluations, not just unit tests. Artifacts are versioned bundles of code + prompt + tool config. Deployment is declarative IaC, one command. Rollback is a `terraform apply` of the previous commit. That's the vision. We're probably 18 months from it being boring and standard.

**Johannes closes:** "So we're paving the road while driving on it."

**Tarlan:** "Exactly. And that's the exciting part — the decisions we make now become the standards other teams copy in two years."

---

## Closing

Johannes wraps with where to find Tarlan's write-up and repo, what the audience should take away, and a standing invitation to come back when the standards are settled — or when they aren't.

**Tarlan's article:** https://dev.to/aws-builders/terraform-your-aws-agentcore-11kl
**Repo:** https://github.com/faye/agentcore-demo
