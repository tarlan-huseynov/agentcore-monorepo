# Podcast Preparation Guide

**Episode:** "There's No Playbook Yet: Shipping AI Agents to Production"
**Channel:** [Lockhead Cloud](https://www.youtube.com/@lockheadcloud)
**Format:** Conversation with Johannes Koch, 20-40 min
**Article:** [Terraform Your AWS AgentCore](https://dev.to/aws-builders/terraform-your-aws-agentcore-11kl)
**Repo:** [github.com/faye/agentcore-demo](https://github.com/faye/agentcore-demo)

---

## How to Use This Document

This isn't a script. It's a **structured talk track** — the bones of your monologue
with enough detail that you can speak confidently without reading anything. Each section
has the core point, the supporting detail, and delivery notes. Internalize the flow,
not the words.

The existing `podcast-plan-johannes.md` covers the conversation structure with Johannes
(his prompts, your answers, transitions). This document goes deeper: it's *your*
preparation for delivering each point with clarity, conviction, and the right level
of technical depth.

---

## Part 1 — Opening: The Gap Nobody Talks About

**Duration:** ~3 min
**Energy:** Relaxed, observational, slightly provocative

### Core Point

There's a massive disconnect right now: everyone's building agents, nobody's
shipping them properly. The AI conversation is dominated by model capabilities,
prompt engineering, and framework choices. The deployment story is an afterthought.

### Talk Track

> *[Casual, like you're talking to a colleague over coffee]*

"So here's the thing that's been bothering me. If you look at the content out
there on AI agents — and there's no shortage of it — it's almost entirely about
the *building*. Which model, which framework, which tools to wire up. The
orchestration layer. The reasoning loop. All valid, all important.

But nobody's talking about what happens *after* you get it working on your laptop.
How do you actually ship this thing? How do you version it? How does your team
collaborate on it? What does the CI/CD pipeline look like? What does your
infrastructure need to look like to support not one runtime, but three
interconnected ones with a gateway, a policy engine, memory persistence, and
five IAM roles?

That's the gap. We've spent decades building standards for deploying conventional
applications. Containers, serverless, orchestration, GitOps — the playbook is
settled. Then agents show up, and all of that gets... complicated."

> *[Pause. Let it land.]*

### Delivery Notes

- **Don't rush the opening.** Set the tone as someone who's been in the trenches,
  not someone pitching a product.
- **The word "complicated" is deliberate** — not "broken" or "impossible." You're
  acknowledging difficulty, not catastrophizing.
- **Key emphasis:** "nobody's talking about what happens *after*" — this is your
  thesis for the episode.

---

## Part 2 — The Established World (Baseline)

**Duration:** ~5 min
**Energy:** Confident, matter-of-fact, building credibility

### Core Point

You've shipped production systems across every deployment paradigm that exists.
The patterns are known, the decision trees are settled. This establishes your
credibility and creates the contrast that makes the agent story land.

### Talk Track

> *[Grounded, experienced — not boastful, just factual]*

"Let me back up. I've been doing this across a lot of different projects and
stacks. Bare metal, VMs, containers on ECS and Kubernetes, serverless with
Lambda, Step Functions for orchestration, fully managed PaaS, hybrid setups.
Different industries, different scales, different team sizes.

And what you notice after enough of these is that the patterns converge.
You develop muscle memory. Containers? ECS or Kubernetes. Event-driven?
Lambda. Orchestration? Step Functions. Infrastructure? Terraform or CDK.
Delivery? GitOps. The pipeline is commit, CI, artifact, staging, prod.

The path is defined. You still make decisions — but the *decision tree* is
known. You're picking from a menu, not inventing the menu."

> *[Beat. Then the turn.]*

"Then I tried to do the same thing with an AI agent. And none of it mapped."

### Delivery Notes

- **Speed through the stack list** — don't dwell on each one, the variety is
  the point.
- **"Decision tree is known"** is the key phrase. Repeat it or rephrase it.
  This is what agents break.
- **The turn ("none of it mapped")** should feel genuine, not dramatic. Like
  you're recalling the actual moment of realization.

---

## Part 3 — What Agents Break

**Duration:** ~8 min
**Energy:** Animated, problem-focused, slightly frustrated (authentically)

### Core Point

Agents aren't services. They're non-deterministic loops that decompose into
multiple interconnected components, each with its own deployment, auth,
and operational concerns. Traditional deployment patterns don't map cleanly.

### Talk Track

#### 3a. The Fundamental Difference

> "A traditional service is deterministic. You call it, it does a thing, it
> returns. You can test the input-output contract. You can reason about failure
> modes. You can scale it horizontally because every instance behaves identically.
>
> An agent is a *loop*. It receives a query, reasons about it, decides which
> tool to call, calls it, looks at the result, decides what to do next. It might
> call three tools, it might call twelve. It might take two seconds or two
> minutes. Non-deterministic by design. That's the whole point — that's what
> makes it useful. But it also means every operational assumption you had about
> deploying a service needs to be re-examined."

#### 3b. The Deployment Unit Problem

> *[This is the insight that makes people lean in]*

"But here's the thing that really caught me. The unit of deployment for an agent
isn't one thing. It's a *constellation*.

Think about what our implementation actually requires to run:
- A main agent runtime — the orchestrator
- Two separate MCP server runtimes — one for Cloud Control API with 14 tools,
  one for Cost Explorer with 7 tools
- A gateway that routes between them and handles tool discovery
- A Cedar policy engine that enforces safety guardrails at the gateway level
- A memory store for session persistence with a summarization strategy
- A Cognito user pool for machine-to-machine authentication between the
  gateway and the MCP runtimes
- Five IAM roles — one per runtime, one for gateway execution, one for
  gateway invocation
- Three CloudWatch log groups for observability
- An S3 bucket for deployment artifacts

That's not a deployment. That's an *infrastructure stack*. And all of it
needs to be in sync. If any piece drifts independently, the agent breaks in
subtle, hard-to-diagnose ways."

> *[Emphasize "subtle, hard-to-diagnose" — this is the pain]*

#### 3c. The Platform Choice Problem

> "And then there's the question everyone asks: where do you even run this?
>
> Lambda? Cold starts hurt when your agent loop runs for 30 seconds. And
> there's a 15-minute execution limit — some agent tasks legitimately need
> longer.
>
> ECS? Now you're managing containers and scaling for something that runs
> in bursts. You're paying for idle capacity or dealing with cold starts
> anyway.
>
> Kubernetes? Serious overhead for what might be a single-tenant workload.
>
> Managed runtime? You're betting on a young service with tooling gaps.
>
> Nobody has a standard answer. Every team is improvising. And that's the
> honest situation."

### Delivery Notes

- **The constellation list is your centerpiece.** Count them off. Let the
  audience feel the weight of it.
- **Don't present yourself as having all the answers.** The honesty about
  the unsettled landscape builds trust.
- **"Improvising" is the right word** — not "struggling" or "failing."
  Teams are smart; the tooling hasn't caught up.

---

## Part 4 — AgentCore as Serverless for Agents

**Duration:** ~5 min
**Energy:** Pragmatic, evaluative — not promotional

### Core Point

AgentCore's pitch is "serverless for agents" — you bring code, AWS handles
compute, scaling, auth, networking. For a multi-runtime agent architecture,
the operational burden reduction is significant. But the service is young and
has real gaps.

### Talk Track

> "So I picked AgentCore. And the reason is simple: the operational surface
> area of what I was building was enormous. Three runtimes, a gateway, memory,
> policy, five IAM roles, OAuth between components. If I had to self-manage
> all of that on ECS or Kubernetes, I'd spend more time on infrastructure
> than on the agent itself.
>
> AgentCore's value proposition is that it absorbs most of that operational
> burden. It's serverless for agents, essentially. You package your code,
> upload it, and AgentCore handles the compute layer — ARM64 Graviton
> instances, auto-scaling, up to 8-hour execution windows. The gateway
> handles tool routing and authentication. Memory handles session persistence.
>
> For our implementation, that means I write a Strands agent in Python,
> point it at the gateway URL, and the gateway knows how to reach both MCP
> servers, handle the OAuth token exchange, discover the 21 tools across
> both servers, and enforce Cedar policies on every tool call. That's a lot
> of complexity that I'm *not* building.
>
> The catch? Tooling maturity. The service is new. You hit edges fast."

> *[Say this directly, not apologetically]*

### Delivery Notes

- **Be balanced.** Praise what works, be candid about what doesn't. The
  audience trusts practitioners, not evangelists.
- **"21 tools" and "5 IAM roles"** — specific numbers create credibility.
  You've counted. You know the system.
- **"You hit edges fast"** is the transition to the Terraform story.

---

## Part 5 — The Starter Kit Gap

**Duration:** ~3 min
**Energy:** Constructive criticism

### Core Point

The official starter toolkit gets you running but doesn't get you to
production. It's imperative — run commands, get resources — with no
declarative record, no version history, no reproducibility.

### Talk Track

> "AWS ships a starter toolkit and a CLI. And they work — they absolutely
> get you from zero to a running agent. Good for a demo, good for a spike.
>
> But it's imperative. You run commands, things get created, and there's no
> declarative record of what exists. No version history. No diff to review
> in a PR. No way to reproduce it exactly on a new account. If something
> breaks and you need to know what changed — you're digging through CLI
> history.
>
> And this is the tension right now in AI tooling broadly, not just AgentCore.
> The mindset in AI tooling is still 'get it working.' The infrastructure
> mindset is 'define it, version it, automate it.' Those two haven't merged
> yet. This project is my attempt to merge them."

### Delivery Notes

- **Don't bash the starter toolkit.** It serves its purpose. Your point is
  that it serves a *different* purpose than what production teams need.
- **"Those two haven't merged yet"** is a quotable line. Deliver it with
  weight.

---

## Part 6 — Why Terraform (The Core Argument)

**Duration:** ~8 min
**Energy:** This is your strongest section. Confident, detailed, opinionated.

### Core Point

Terraform manages the full dependency graph of an agent deployment in a single
command. One monorepo, one `terraform apply`, everything versioned and reviewable.
But there are real provider gaps — and how you handle those gaps is itself a
lesson in production engineering.

### Talk Track

#### 6a. The Value Proposition

> "One monorepo. Application code, MCP server code, all Terraform — same repo,
> same commit, same PR. `terraform apply` builds the Python packages, uploads
> to S3, deploys all three runtimes, wires the gateway, sets up IAM, configures
> memory and policy. One command, full stack.
>
> Everything is versioned. Every change is a diff you can review. Every
> deployment is reproducible. This is the IaC value proposition that we've
> proven out over the last decade with traditional infrastructure — now
> applied to agent infrastructure."

#### 6b. The _CODE_VERSION Trick

> *[This is a great technical detail — it shows depth]*

"One thing we had to solve that's specific to AgentCore: the runtime caches
your deployment ZIP on initial creation. You update the code in S3, but
AgentCore doesn't know to re-fetch it. Nothing redeploys.

So we do something clever in Terraform. We hash all the Python source files
and inject the hash as an environment variable called `_CODE_VERSION`. The
agent code never reads this variable. But when the hash changes, Terraform
sees a config change on the runtime, which triggers AgentCore to re-fetch
the code from S3.

It's a hack? Kind of. But it's a *principled* hack — deterministic,
automatic, zero manual intervention. And each MCP server only redeploys
when *its* specific code changes, not when any code changes."

> *[Smile when you say "principled hack" — own it]*

#### 6c. The Provider Gaps (Be Honest)

> "Now, here's where it gets real. The Terraform AWS provider doesn't fully
> cover AgentCore yet. And you only find this out when you're knee-deep in
> implementation.
>
> **Gap one:** Gateway targets. The provider silently drops the `grantType`
> field. You need `CLIENT_CREDENTIALS` for the gateway to fetch Cognito
> Bearer tokens and authenticate to the MCP runtimes. The provider just...
> doesn't send it. So we manage targets via a shell script wrapped in a
> `null_resource`, triggered by content hashes.
>
> **Gap two:** The Cedar policy engine. No Terraform resource exists for it
> at all. Same workaround — `null_resource` plus AWS CLI.
>
> **Gap three:** Two fields on the gateway resource — `description` and
> `protocol_configuration` — aren't read back from the API after creation.
> So every `terraform plan` shows phantom changes. Fix: `ignore_changes`
> lifecycle block.
>
> These aren't blockers. But they're the kind of thing that costs you a full
> day if you don't know about them. That's why the article documents every
> single one."

#### 6d. Why the Workarounds Are Still Worth It

> *[This is the mature take — don't just complain, explain why you accepted it]*

"The question people ask is: if you need shell scripts and `null_resource`
workarounds, why bother with Terraform at all? Why not just script the
whole thing?

Because even with workarounds, those scripts are *inside the dependency
graph*. They execute at the right time, in the right order, triggered by
the right changes. The gateway target script only runs when a runtime ARN
changes or the MCP entrypoint code changes. The policy script only runs
when the Cedar policy file changes. And if the gateway gets replaced,
`replace_triggered_by` ensures the policy engine gets re-attached
automatically.

That's the difference between 'I have a script I run after deploy' and
'my infrastructure tool understands when to run the script.' One scales
to a team. The other doesn't.

And when the provider catches up — which it will — those `null_resource`
blocks become clean resource declarations and the shell scripts get deleted.
The rest of the Terraform stays exactly the same."

### Delivery Notes

- **The three gaps are your storytelling device.** Number them clearly.
  The audience remembers structured lists.
- **"Principled hack"** and **"inside the dependency graph"** are your
  memorable phrases in this section. Practice delivering them naturally.
- **Don't rush the "why workarounds are worth it" section.** This is where
  you demonstrate senior-level thinking — the ability to accept imperfection
  in service of a larger architectural goal.

---

## Part 7 — Live Demo: The Full Lifecycle

**Duration:** ~8-10 min
**Energy:** Hands-on, showing not telling. Calm pace — let the terminal breathe.

### Core Point

Everything you've been talking about is real. Show the agent working, make a
change, deploy it, and prove the change took effect. This is the section that
converts skeptics.

### Why This Demo

The Cedar policy change is the strongest possible demo because:
- It's a **1-line edit** (fast on camera, no coding)
- The **before/after is dramatic** (agent can create → agent is blocked)
- It shows **targeted deployment** (only the policy script re-runs, not everything)
- It tells the **safety guardrails story** (the whole point of Cedar)
- The **revert proves reproducibility** (put it back, apply again, works again)

### Pre-Demo Setup (Do Before Recording)

```bash
# Terminal 1: Have the repo open in your editor with safety.cedar visible
# Terminal 2: Have cli_remote.py ready
cd /path/to/agentcore-demo
export AWS_PROFILE=tarlan
export AWS_REGION=eu-central-1

# Verify agent is responding (dry run)
uv run python cli_remote.py -q "What time is it?"
```

### Demo Script — 4 Acts

---

#### Act 1 — "The Agent Works" (~2 min)

> *[Share your terminal. Invoke the deployed agent.]*

"Let me show you this running. I'm going to invoke the deployed agent —
this is hitting the actual AgentCore runtime in eu-central-1."

**Query 1 (read-only, warms up the audience):**
```
uv run python cli_remote.py -q "List my S3 buckets in eu-central-1"
```

> *[While it runs, narrate what's happening:]*

"So right now, the agent receives my query, reasons about it, decides it
needs the `list_resources` tool, sends an MCP call through the gateway,
the gateway routes it to the CCAPI MCP server runtime, which calls the
Cloud Control API, and the result comes back through the same chain."

> *[Results appear. Point at the tool calls in the output.]*

"See those tool calls? Each one went through the gateway, got checked
against the Cedar policy — read-only tools are always permitted — and
reached the MCP server. That's three runtimes, a gateway, and a policy
engine, all in one natural language query."

**Delivery note:** Don't rush. Let the audience see the output. The
tool call trace is the proof.

---

#### Act 2 — "The Agent Creates" (~2 min)

> *[This establishes that write operations work — the contrast comes next.]*

"Now let's do something more interesting. Let's create actual infrastructure."

**Query 2 (write operation):**
```
uv run python cli_remote.py -q "Create an SQS queue called podcast-demo"
```

> *[While it runs:]*

"The agent is going to look up the SQS schema, figure out the desired
state JSON, explain what it's about to do, and then call `create_resource`
through Cloud Control API. The Cedar policy allows SQS creation — it's
in the allowlist."

> *[Results appear. The queue is created.]*

"That's a real SQS queue. It exists now. The agent figured out the schema,
built the configuration, and created it — all from 'create an SQS queue
called podcast-demo.'"

**Delivery note:** Emphasize "real." This isn't a mock. This isn't a demo
environment. This is your AWS account.

> *[Clean up: ask the agent to delete it, or leave it — your call.]*

---

#### Act 3 — "The Policy Change" (~3 min)

> *[This is the pivot. Switch to your editor.]*

"Now here's where it gets interesting. I'm going to change one thing."

> *[Open `terraform/policies/safety.cedar` in the editor. Show the
> create/update section. Point at the SQS line.]*

"This is the Cedar policy. Section 2 — the allowlist for resource creation.
See `AWS::SQS::Queue` on line 49? I'm going to remove it."

> *[Delete the line. Save the file. Keep it on screen for a beat.]*

"One line. Now let's deploy."

```bash
cd terraform && terraform apply
```

> *[While Terraform runs, narrate what's happening:]*

"Watch what Terraform does here. It sees that `safety.cedar` changed —
the file hash is different. So it re-runs the policy setup script. But
it does NOT rebuild the Python packages. It does NOT redeploy the runtimes.
It does NOT touch the gateway or memory. Only the policy.

That's the dependency graph. It knows exactly what changed and what needs
to update."

> *[Terraform finishes. Only `null_resource.policy_setup` was replaced.]*

"Done. The Cedar policy is now enforced at the gateway. Let's test it."

**Delivery note:** The Terraform output is your visual proof. Point at
which resources changed (1 replaced) vs which didn't (everything else).
If the audience sees `null_resource.policy_setup: Destroying...` and
`null_resource.policy_setup: Creating...` while everything else is
untouched — that's the money shot.

---

#### Act 4 — "The Guardrail Enforces" (~2 min)

> *[Back to the CLI. Same query as Act 2.]*

"Same agent. Same query. Let's see what happens."

**Query 3 (same write operation, now blocked):**
```
uv run python cli_remote.py -q "Create an SQS queue called podcast-demo-2"
```

> *[The agent tries, but the Cedar policy blocks the `create_resource`
> call for SQS. The agent gets an error or denial.]*

"Blocked. The agent tried to call `create_resource` for SQS, the gateway
checked the Cedar policy, SQS is no longer in the allowlist, denied.

Same code. Same runtime. Same agent. One line in a policy file changed
the boundary of what the agent can do. That's deterministic safety
guardrails — not prompt engineering, not 'please don't do this,' but
actual enforcement at the infrastructure level."

> *[Pause. Let it land.]*

**Delivery note:** This is your strongest moment. The contrast between
Act 2 (it worked) and Act 4 (it's blocked) is visceral. Don't undercut
it by immediately explaining — let the audience sit with it for a second.

---

#### Optional: Act 5 — "The Revert" (~1 min)

> *[If time allows — proves reproducibility.]*

"And if I put that line back..."

> *[Add `AWS::SQS::Queue` back to the Cedar policy. `terraform apply`.]*

"One apply. Policy restored. The agent can create SQS again. Full lifecycle:
change, deploy, enforce, revert. All versioned, all reviewable, all in one
command."

---

### Fallback Plan

If the live demo fails (network, AgentCore latency, API issues):

1. **Have a screen recording ready.** Record the demo beforehand as backup.
   Don't announce it's pre-recorded unless asked.
2. **If it's slow:** Narrate what's happening while waiting. "AgentCore is
   routing through the gateway, checking policy, calling Cloud Control API..."
   Latency is actually a feature — it proves real work is happening.
3. **If it errors:** Debug live. This is authentic. "See — this is what I
   mean about hitting edges. Let me check the logs." Use `search_logs` to
   diagnose. The audience loves seeing real troubleshooting.

### What to Show on Screen

| Moment | What's visible |
|--------|---------------|
| Act 1-2 | Terminal with `cli_remote.py` output — tool calls + results |
| Act 3 (edit) | Editor showing `safety.cedar` — the 1-line delete |
| Act 3 (deploy) | Terminal with `terraform apply` — resource change summary |
| Act 4 | Terminal with `cli_remote.py` — the denial/block message |

### Key Lines to Say During Demo

- "Three runtimes, a gateway, and a policy engine — one natural language query"
- "That's a real SQS queue. It exists now."
- "Watch what Terraform does. Only the policy updates. Everything else is untouched."
- "Same code. Same runtime. Same agent. One line changed the boundary."
- "Not prompt engineering. Actual enforcement at the infrastructure level."

---

## Part 8 — War Stories (ARM64 + Packaging)

**Duration:** ~2 min (or skip if time is tight)
**Energy:** War story — brief, specific, useful

### Core Point

AgentCore runs on Graviton (ARM64). If you build Python packages on x86,
you get silent import failures at runtime. This is a packaging problem
that catches everyone.

### Talk Track

> "Quick war story that'll save someone a day of debugging. AgentCore
> runtimes run on Graviton — ARM64. If you're building your Python packages
> on an x86 laptop, the native binaries won't work. And the failure mode
> is silent — your deployment succeeds, your runtime starts, and then you
> get an import error deep in a C extension.
>
> We use `uv` with explicit platform targeting:
> `--python-platform aarch64-manylinux2014 --only-binary=:all:`. That
> forces ARM64 wheels and prevents source compilation fallbacks.
>
> Also: AgentCore's filesystem at `/var/task` is read-only. Some Python
> packages — like the CCAPI MCP server — try to write schema caches
> next to their source files at import time. That crashes immediately.
> We patch the cache directory to `/tmp` during packaging. Small fix,
> but you'd never find it without hitting the error first."

### Delivery Notes

- **Optional section.** Include if the conversation is flowing and you
  have time. Skip if you're running long.
- **"Silent import failures"** — emphasize the word "silent." That's what
  makes it painful.

---

## Part 9 — The Deployment Sequence (For Visual Thinkers)

**Duration:** ~3 min
**Energy:** Technical walkthrough, steady pace

### Core Point

A single `terraform apply` orchestrates a complex dependency chain:
build, upload, provision, configure. Understanding the sequence helps
people see why IaC matters for agents.

### Talk Track

> "Let me walk through what actually happens when you run `terraform apply`.
>
> First, Terraform creates the S3 bucket for deployment artifacts.
>
> Then it runs the build scripts — cross-compiling three Python packages
> for ARM64 and zipping them up. These get uploaded to S3.
>
> In parallel, it creates the IAM roles — five of them — and the Cognito
> user pool for machine-to-machine auth.
>
> Then the three runtimes get created, each pointing to its ZIP in S3.
> The main runtime gets the gateway URL as an environment variable so it
> knows where to send MCP tool calls.
>
> Then the gateway comes up. A shell script registers both MCP runtimes
> as gateway targets with the right OAuth configuration.
>
> Then memory gets provisioned — the memory resource plus a summarization
> strategy.
>
> Finally, the Cedar policy engine gets created and attached to the gateway.
>
> All of that, one command. And every piece knows its dependencies — if the
> gateway target script needs to re-run because a runtime changed, it
> re-runs automatically. That's the dependency graph doing its job."

### Delivery Notes

- **Walk through it like a tour guide**, not a spec sheet. Each step
  should feel like "and then this happens, which enables this."
- **"One command"** — say it once at the beginning, once at the end.
  Bookend the sequence.

---

## Part 10 — Open Questions and Forward Look

**Duration:** ~8 min
**Energy:** Thoughtful, speculative, honest about uncertainty

### Core Point

The agent deployment space is genuinely unsettled. Terraform is the best
tool available today, but purpose-built tooling may emerge. Testing
non-deterministic agents in CI is an unsolved problem. The decisions
teams make now become the standards others adopt.

### Talk Track

#### Q: Is Terraform the long-term answer for agents?

> "Honest answer — maybe not forever. Right now it's the most mature IaC
> tool that can express both code packaging and infrastructure configuration
> in a single workflow. CDK is a contender. But purpose-built agent
> deployment tooling doesn't exist yet. Someone will build it. Until then,
> Terraform works — imperfectly but meaningfully."

#### Q: How do you test a non-deterministic agent in CI?

> "This is the genuinely unsolved problem in the space. Unit tests on pure
> helper functions work. Integration tests on individual tool behavior work.
> We can verify that the `search_logs` tool returns the right format, or that
> the orchestrator creates a session manager correctly.
>
> But end-to-end agent behavior testing — did the agent *reason* correctly?
> Did it pick the right tools in the right order? Did it ask for confirmation
> before creating infrastructure? — that's a fundamentally different kind of
> test. It's more like evaluation than verification.
>
> AgentCore Evaluations is one answer. LLM-as-judge patterns are another.
> But the field is early and nobody has a proven CI pipeline for agent
> quality. That's the next frontier."

#### Q: Will managed runtimes become the ECS of the agent era?

> "That's the bet I'm making by choosing AgentCore. The analogy holds — ECS
> abstracted container orchestration, AgentCore abstracts agent runtime
> orchestration. The question is adoption speed and tooling maturity.
>
> I think managed runtimes win for the same reason ECS won over raw EC2
> for containers. The operational surface area is too large for most teams
> to self-manage. Three runtimes, a gateway, memory, policy, auth — that's
> a platform, not a deployment. And platforms should be managed."

#### Q: What does a mature agent SDLC look like in 2-3 years?

> *[End with vision — leave the audience thinking]*

"Here's what I think it looks like. Commit triggers a pipeline. Pipeline
runs agent evaluations — not just unit tests, but behavioral evaluations.
Artifacts are versioned bundles: code, prompt, tool configuration, Cedar
policies, all together. Deployment is declarative IaC, one command.
Rollback is a `terraform apply` of the previous commit.

We're probably 18 months from that being boring and standard. Right now
it's frontier work. The decisions teams make today become the patterns
everyone else copies in two years."

> *[Deliver the last line looking into the camera/at Johannes.
> It's your closing thesis.]*

### Delivery Notes

- **This section should feel like a real conversation**, not prepared
  answers. Let Johannes's questions guide the flow.
- **"Boring and standard"** is a great phrase. The goal of all platform
  engineering is to make things boring. That's the aspiration.
- **Don't overclaim.** "Maybe not forever" and "the field is early" build
  more trust than confident predictions.

---

## Part 11 — Close

**Duration:** ~2 min
**Energy:** Warm, direct, forward-looking

### Talk Track

> "What I want people to take away from this is one thing: deploying agents
> is an infrastructure problem, not just a code problem. And we have good
> tools for infrastructure problems. Terraform isn't perfect for this yet,
> but it's far better than scripts and CLI commands held together by tribal
> knowledge.
>
> The article walks through every decision, every workaround, every provider
> gap — so the next person doesn't spend a week rediscovering what I
> documented in a weekend. The repo is open. Fork it, adapt it, tell me
> where I'm wrong."

### Delivery Notes

- **"Infrastructure problem, not just a code problem"** — this is your
  one-sentence thesis. If people remember nothing else, they should
  remember this.
- **End with an invitation**, not a conclusion. "Tell me where I'm wrong"
  signals confidence and openness.

---

## Quick Reference Card

Keep this in front of you during the podcast — glance, don't read.

### Numbers That Build Credibility

| What | Number |
|------|--------|
| Agent runtimes | 3 |
| MCP tools (total) | 21 (14 CCAPI + 7 Cost Explorer) |
| IAM roles | 5 |
| Gateway targets | 2 |
| AWS resource types via Cloud Control | 1,100+ |
| Cedar policy sections | 4 (read-only, create/update, delete, cost) |
| Allowed create/update resource types | 11 |
| Allowed delete resource types | 6 |

### Key Phrases to Land

- "The unit of deployment is a constellation, not a container"
- "Nobody's talking about what happens after you get it working on your laptop"
- "The decision tree is known — until agents"
- "Those two mindsets haven't merged yet"
- "A principled hack"
- "Inside the dependency graph"
- "When the provider catches up, the shell scripts get deleted"
- "Deploying agents is an infrastructure problem, not just a code problem"
- "We're paving the road while driving on it"
- "Boring and standard — that's the aspiration"
- "Same code. Same runtime. Same agent. One line changed the boundary."
- "Not prompt engineering — actual enforcement at the infrastructure level"

### The Three Provider Gaps (Numbered for Clarity)

1. **Gateway targets** — missing `grantType` (OAuth). Workaround: CLI script
   in `null_resource`.
2. **Policy engine** — no TF resource. Workaround: CLI script in `null_resource`.
3. **Gateway drift** — `description` + `protocol_configuration` not read back.
   Workaround: `ignore_changes`.

### Transition Lines Between Sections

- "Then agents showed up — and none of that mapped."
- "That's not a deployment. That's an infrastructure stack."
- "The catch? Tooling maturity. You hit edges fast."
- "Those two mindsets haven't merged yet. This project is my attempt to merge them."
- "So we have a working approach. But is it *the* approach?"
- "The decisions teams make today become the patterns everyone else copies in two years."

---

## Anti-Patterns to Avoid

1. **Don't sell AgentCore.** You're a practitioner, not a product manager.
   Be candid about gaps. Your credibility comes from honesty.

2. **Don't bash CLI/starter toolkit.** They serve their purpose. Your argument
   is about what *production teams* need, not that other approaches are wrong.

3. **Don't get lost in code.** This is a podcast, not a live coding session.
   Reference the repo, say "here's what the code does," but don't recite
   Terraform blocks verbatim.

4. **Don't overuse "non-deterministic."** Use it once or twice to set the frame,
   then switch to concrete examples. "The agent might call three tools or
   twelve" is more vivid than "non-deterministic behavior."

5. **Don't predict timelines confidently.** "18 months" is fine as a rough
   estimate. Don't say "by Q3 2027 every team will..." — you'll date yourself.

6. **Don't skip the war stories.** The ARM64 gotcha, the `_CODE_VERSION` trick,
   the silent `grantType` drop — these are the moments that make the audience
   trust you. They prove you built this, not just designed it.
