# Podcast Preparation Guide

**Episode:** "There's No Playbook Yet: Shipping AI Agents to Production"
**Channel:** [Lockhead Cloud](https://www.youtube.com/@lockheadcloud)
**Format:** Conversation with Johannes Koch, 20-40 min
**Article:** [Terraform Your AWS AgentCore](https://dev.to/aws-builders/terraform-your-aws-agentcore-11kl)
**Repo:** [github.com/faye/agentcore-demo](https://github.com/faye/agentcore-demo)

---

## How to Use This Document

This isn't a script. It's a **structured talk track** — the bones of your
monologue with enough detail that you can speak confidently without reading
anything. Each section has the core point, the supporting detail, and
delivery notes. Internalize the flow, not the words.

**Target runtime:** ~28 min speaking + ~5-7 min Johannes questions = **33-35 min**

**Structure:** 6 sections, one live demo centerpiece.

| # | Section | Min |
|---|---------|-----|
| 1 | Opening: The Gap + What I Built | 3 |
| 2 | The Known World + What Agents Break | 5 |
| 3 | AgentCore + Why Terraform | 6 |
| 4 | **Live Demo: The Full Lifecycle** | 8 |
| 5 | Open Questions | 5 |
| 6 | Close | 2 |
| | **Speaking total** | **~29 min** |

---

## Part 1 — Opening: The Gap + What I Built

**Duration:** ~3 min
**Energy:** Relaxed, observational, then grounding with a concrete example

### Core Point

There's a massive disconnect: everyone's building agents, nobody's shipping
them properly. And before we go further — here's what the agent actually
does.

### Talk Track

#### 1a. The Gap (~1.5 min)

> *[Casual, like you're talking to a colleague over coffee]*

"So here's the thing that's been bothering me. If you look at the content
out there on AI agents — and there's no shortage of it — it's almost
entirely about the *building*. Which model, which framework, which tools
to wire up. The orchestration layer. The reasoning loop. All valid.

But nobody's talking about what happens *after* you get it working on your
laptop. How do you actually ship this thing? How do you version it? How
does your team collaborate on it? What does the CI/CD pipeline look like?

We've spent decades building standards for deploying conventional
applications. Containers, serverless, orchestration, GitOps — the playbook
is settled. Then agents show up, and all of that gets... complicated."

> *[Pause. Let it land.]*

#### 1b. What I Built (~1.5 min)

> *[Shift from abstract to concrete. Give them the mental model.]*

"So let me tell you what I actually built, because that'll ground
everything we talk about today.

It's an Infrastructure Bootstrapper. You tell it in plain English — 'I need
a DynamoDB table with an API Gateway' — and it figures out the CloudFormation
schema, generates the desired state, explains what it's about to create, and
calls the Cloud Control API to create it. Real infrastructure, real AWS
account. Not a simulation.

It also analyzes your cloud costs through Cost Explorer and searches
CloudWatch Logs — so you can ask it 'what am I spending on Lambda this
month?' or 'show me recent errors in my log groups.'

Under the hood, that's three runtimes. The main agent — built on
the Strands SDK — is the orchestrator. A Cloud Control API MCP server
with 14 tools covering 1,100+ AWS resource types. A Cost Explorer MCP
server with 7 tools. All three connected through an AgentCore Gateway.
And sitting in front of the gateway, Cedar policy guardrails controlling
exactly what the agent is allowed to create, update, or delete.

That's 21 tools, 3 runtimes, a gateway, a policy engine, memory for
session persistence, 5 IAM roles, and a Cognito setup for machine-to-machine
auth between the components. All of which needs to be deployed, configured,
and kept in sync."

> *[Beat.]*

"And that's the problem."

### Delivery Notes

- **Don't rush 1b.** This is the audience's mental model for the entire
  episode. If they don't understand what the agent does, the demo won't
  land.
- **"Real infrastructure, real AWS account"** — say it clearly. This isn't
  a toy.
- **End on "that's the problem"** — bridges directly to Part 2.

---

## Part 2 — The Known World + What Agents Break

**Duration:** ~5 min
**Energy:** Confident baseline, then animated problem-framing

### Core Point

You've shipped production systems across every deployment paradigm. The
patterns converge, the playbook is known. Agents break that playbook
because they're non-deterministic loops that decompose into multiple
interconnected components.

### Talk Track

#### 2a. The Known World (~1.5 min)

> *[Grounded, experienced — not boastful, just factual]*

"Quick context on where I'm coming from. I've shipped across a lot of
stacks: bare metal, VMs, containers on ECS and Kubernetes, serverless
Lambda, Step Functions for orchestration, fully managed PaaS, hybrid
setups. Different industries, different scales.

What you notice after enough of these is that the patterns converge.
Containers? ECS or Kubernetes. Event-driven? Lambda. Orchestration?
Step Functions. Infrastructure? Terraform or CDK. Delivery? GitOps.
Commit, CI, artifact, staging, prod.

The path is defined. You still make decisions — but the *decision tree*
is known. You're picking from a menu, not inventing the menu."

> *[Beat. Then the turn.]*

"Then I tried to do the same thing with an AI agent. And none of it
mapped."

#### 2b. What Agents Break (~3.5 min)

> *[More animated — this is the problem statement]*

"A traditional service is deterministic. You call it, it does a thing,
it returns. You can test the input-output contract. You can reason about
failure modes.

An agent is a *loop*. It receives a query, reasons about it, decides
which tool to call, calls it, looks at the result, decides what to do
next. It might call three tools, it might call twelve. It might take two
seconds or two minutes. Non-deterministic by design. That's what makes it
useful — but it means every operational assumption you had about deploying
a service needs to be re-examined."

> *[Now the real insight — lean into this]*

"But here's what really caught me. The unit of deployment for an agent
isn't one thing. It's a *constellation*.

Think about what I just described. Three runtimes. A gateway routing
between them with tool discovery. A Cedar policy engine. A memory store.
A Cognito user pool for machine-to-machine auth. Five IAM roles. Three
log groups. An S3 bucket for artifacts.

That's not a deployment. That's an infrastructure stack. And all of it
needs to be in sync. If any piece drifts independently, the agent breaks
in subtle, hard-to-diagnose ways. The gateway can't route because a
target config is stale. The policy engine strips tools that haven't been
registered. Memory fails because the session ID format doesn't match.

And then: where do you even run this? Lambda? Cold starts hurt long
agent loops. ECS? You're managing containers for burst workloads. The
honest answer is nobody has a standard. Every team is improvising."

> *[Transition]*

"So I decided to pick one approach and document everything — including
the ugly parts."

### Delivery Notes

- **"Constellation"** is your word for this section. Use it once, clearly.
  It's memorable.
- **Speed through the stack list in 2a** — the variety is the point, not
  the detail.
- **The turn ("none of it mapped")** should feel genuine, not dramatic.
- **Count the components** when listing them. Let the audience feel the
  weight.

---

## Part 3 — AgentCore + Why Terraform

**Duration:** ~6 min
**Energy:** Pragmatic, opinionated, technically detailed

### Core Point

AgentCore is serverless for agents — it absorbs the operational burden of
multi-runtime agent architectures. But the official tooling is imperative
and un-versioned. Terraform brings IaC discipline to agent deployment,
with real provider gaps that you work around.

### Talk Track

#### 3a. Why AgentCore (~1.5 min)

> "AgentCore's pitch is serverless for agents. You bring the code, AWS
> handles compute, scaling, auth, networking. ARM64 Graviton instances,
> auto-scaling, up to 8-hour execution windows.
>
> For what I'm building — three runtimes, a gateway, memory, policy,
> five IAM roles, OAuth between components — if I had to self-manage all
> of that on ECS or Kubernetes, I'd spend more time on infrastructure
> than on the agent itself. AgentCore absorbs that operational burden.
>
> The catch? Tooling maturity. The service is new. You hit edges fast."

#### 3b. Why Not Just the CLI (~1 min)

> "AWS ships a starter toolkit and CLI. They get you running — great for
> a demo, great for a spike.
>
> But it's imperative. You run commands, things get created, and there's
> no declarative record of what exists. No version history. No diff to
> review in a PR. No way to reproduce it exactly on a new account.
>
> The mindset in AI tooling is still 'get it working.' The infrastructure
> mindset is 'define it, version it, automate it.' Those two haven't
> merged yet. This project is my attempt to merge them."

#### 3c. One Monorepo, One Apply (~1.5 min)

> "One monorepo. Application code, MCP server code, all Terraform —
> same repo, same commit, same PR. `terraform apply` builds the Python
> packages, cross-compiles for ARM64, uploads to S3, deploys all three
> runtimes, wires the gateway, sets up IAM, configures memory and policy.
> One command, full stack.
>
> One thing we had to solve that's specific to AgentCore: the runtime
> caches your deployment ZIP. You update code in S3, but nothing
> redeploys. So we hash all the Python source files and inject the hash
> as an environment variable called `_CODE_VERSION`. The agent never
> reads it — but when the hash changes, Terraform sees a config change
> and AgentCore re-fetches from S3. Principled hack — deterministic,
> automatic, zero manual intervention."

#### 3d. The Three Provider Gaps (~2 min)

> "Now here's where it gets real. The Terraform AWS provider doesn't
> fully cover AgentCore yet.
>
> **Gap one:** Gateway targets. The provider silently drops the `grantType`
> field — you need `CLIENT_CREDENTIALS` for the Cognito OAuth flow. It
> just doesn't send it. Workaround: shell script in a `null_resource`,
> triggered by content hashes.
>
> **Gap two:** The Cedar policy engine. No Terraform resource exists at
> all. Same workaround — `null_resource` plus AWS CLI.
>
> **Gap three:** Two gateway fields aren't read back from the API after
> creation. Every `terraform plan` shows phantom changes. Fix:
> `ignore_changes` lifecycle block.
>
> But here's why the workarounds are still worth it. Those scripts are
> *inside the dependency graph*. They execute at the right time, in the
> right order, triggered by the right changes. That's the difference
> between 'I have a script I run after deploy' and 'my infrastructure
> tool knows when to run the script.' One scales to a team.
>
> And when the provider catches up — the `null_resource` blocks become
> clean resource declarations and the shell scripts get deleted."

### Delivery Notes

- **"Those two haven't merged yet"** — deliver with weight. It's a
  quotable line.
- **Number the three gaps clearly.** The audience remembers structured
  lists.
- **"Principled hack"** — smile when you say it. Own it.
- **Don't rush the "why workarounds are worth it."** This is senior-level
  thinking — accepting imperfection in service of a larger goal.

---

## Part 4 — Live Demo: The Full Lifecycle

**Duration:** ~8 min
**Energy:** Hands-on, showing not telling. Calm pace — let the terminal breathe.

### Core Point

Everything you've been talking about is real. Show the agent working, make
a change, deploy it, prove the change took effect. This is the section
that converts skeptics.

### Why This Demo

The Cedar policy change is the strongest possible demo because:
- It's a **1-line edit** (fast on camera, no coding)
- The **before/after is dramatic** (agent can create → agent is blocked)
- It shows **targeted deployment** (only the policy script re-runs)
- It tells the **safety guardrails story** (the whole point of Cedar)
- The **revert proves reproducibility**

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

> *[While it runs, narrate:]*

"Right now the agent receives my query, reasons about it, decides it needs
the `list_resources` tool, sends an MCP call through the gateway, the
gateway routes it to the CCAPI MCP server runtime, which calls Cloud
Control API, and the result comes back through the same chain."

> *[Results appear. Point at the tool calls.]*

"See those tool calls? Each one went through the gateway, got checked
against the Cedar policy — read-only tools are always permitted — and
reached the MCP server. Three runtimes, a gateway, and a policy engine,
all in one natural language query."

**Delivery note:** Don't rush. Let the audience see the output.

---

#### Act 2 — "The Agent Creates" (~2 min)

> *[Establish that write operations work — the contrast comes next.]*

"Now let's create actual infrastructure."

**Query 2 (write operation):**
```
uv run python cli_remote.py -q "Create an SQS queue called podcast-demo"
```

> *[While it runs:]*

"The agent is going to look up the SQS schema, figure out the desired
state JSON, and call `create_resource` through Cloud Control API. The
Cedar policy allows SQS creation — it's in the allowlist."

> *[Results appear.]*

"That's a real SQS queue. It exists now in my AWS account. The agent
figured out the schema, built the configuration, and created it — all
from 'create an SQS queue called podcast-demo.'"

**Delivery note:** Emphasize "real." This isn't a mock.

---

#### Act 3 — "The Policy Change" (~3 min)

> *[The pivot. Switch to your editor.]*

"Now here's where it gets interesting. I'm going to change one thing."

> *[Open `terraform/policies/safety.cedar`. Show the create/update
> section. Point at the SQS line.]*

"This is the Cedar policy. Section 2 — the allowlist for resource
creation. See `AWS::SQS::Queue` on line 49? I'm going to remove it."

> *[Delete the line. Save. Keep it on screen for a beat.]*

"One line. Now let's deploy."

```bash
cd terraform && terraform apply
```

> *[While Terraform runs:]*

"Watch what Terraform does here. It sees that `safety.cedar` changed —
the file hash is different. So it re-runs the policy setup script.
But it does NOT rebuild the Python packages. It does NOT redeploy the
runtimes. It does NOT touch the gateway or memory. Only the policy.

That's the dependency graph. It knows exactly what changed and what
needs to update."

> *[Terraform finishes. Only `null_resource.policy_setup` replaced.]*

"Done. Let's test it."

**Delivery note:** The Terraform output is your visual proof. Point at
which resources changed (1 replaced) vs which didn't (everything else).
That's the money shot.

---

#### Act 4 — "The Guardrail Enforces" (~1.5 min)

> *[Back to the CLI. Same query as Act 2.]*

"Same agent. Same query. Let's see what happens."

**Query 3:**
```
uv run python cli_remote.py -q "Create an SQS queue called podcast-demo-2"
```

> *[The Cedar policy blocks the `create_resource` call for SQS.]*

"Blocked. The agent tried to call `create_resource` for SQS, the
gateway checked the Cedar policy, SQS is no longer in the allowlist,
denied.

Same code. Same runtime. Same agent. One line in a policy file changed
the boundary of what the agent can do. That's deterministic safety
guardrails — not prompt engineering, not 'please don't do this,' but
actual enforcement at the infrastructure level."

> *[Pause. Let it land.]*

**Delivery note:** This is your strongest moment. The contrast between
Act 2 (it worked) and Act 4 (it's blocked) is visceral. Don't undercut
it by immediately explaining — let the audience sit with it.

---

### Fallback Plan

If the live demo fails (network, AgentCore latency, API issues):

1. **Have a screen recording ready.** Record the demo beforehand as backup.
2. **If it's slow:** Narrate what's happening. Latency proves real work
   is happening.
3. **If it errors:** Debug live. "See — this is what I mean about hitting
   edges." Use `search_logs` to diagnose. Authentic troubleshooting builds
   trust.

### What to Show on Screen

| Moment | What's visible |
|--------|---------------|
| Act 1-2 | Terminal with `cli_remote.py` — tool calls + results |
| Act 3 (edit) | Editor showing `safety.cedar` — the 1-line delete |
| Act 3 (deploy) | Terminal with `terraform apply` — resource change summary |
| Act 4 | Terminal with `cli_remote.py` — the denial/block message |

---

## Part 5 — Open Questions

**Duration:** ~5 min
**Energy:** Thoughtful, honest about uncertainty

### Core Point

Agent deployment is genuinely unsettled. Testing non-deterministic agents
in CI is the frontier problem. The decisions made now become future
standards.

### Talk Track

#### Q: How do you test a non-deterministic agent in CI?

> "This is the genuinely unsolved problem. Unit tests on pure helper
> functions work. Integration tests on tool behavior work. We can verify
> that `search_logs` returns the right format.
>
> But end-to-end agent behavior testing — did the agent *reason*
> correctly? Did it pick the right tools in the right order? Did it ask
> for confirmation before creating infrastructure? — that's a
> fundamentally different kind of test. It's more like evaluation than
> verification.
>
> AgentCore Evaluations is one answer. LLM-as-judge patterns are
> another. But the field is early and nobody has a proven CI pipeline
> for agent quality. That's the next frontier."

#### Q: What does a mature agent SDLC look like in 2-3 years?

> "Commit triggers a pipeline. Pipeline runs agent evaluations — not
> just unit tests, but behavioral evaluations. Artifacts are versioned
> bundles: code, prompt, tool configuration, Cedar policies, all
> together. Deployment is declarative IaC, one command. Rollback is a
> `terraform apply` of the previous commit.
>
> We're probably 18 months from that being boring and standard. Right now
> it's frontier work. The decisions teams make today become the patterns
> everyone else copies in two years."

### Delivery Notes

- **Let these feel like conversation**, not prepared answers. Johannes
  will naturally riff on these.
- **"Boring and standard"** — the goal of platform engineering is to make
  things boring. That's the aspiration.
- **Don't overclaim.** "The field is early" builds more trust than
  confident predictions.

---

## Part 6 — Close

**Duration:** ~2 min
**Energy:** Warm, direct, forward-looking

### Talk Track

> "What I want people to take away is one thing: deploying agents is an
> infrastructure problem, not just a code problem. And we have good tools
> for infrastructure problems. Terraform isn't perfect for this yet, but
> it's far better than scripts and CLI commands held together by tribal
> knowledge.
>
> The article walks through every decision, every workaround, every
> provider gap — so the next person doesn't spend a week rediscovering
> what I documented. The repo is open. Fork it, adapt it, tell me where
> I'm wrong."

### Delivery Notes

- **"Infrastructure problem, not just a code problem"** — one-sentence
  thesis. If they remember nothing else, remember this.
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

- "Nobody's talking about what happens after you get it working on your laptop"
- "The decision tree is known — until agents"
- "The unit of deployment is a constellation, not a container"
- "Those two mindsets haven't merged yet"
- "A principled hack"
- "Inside the dependency graph"
- "When the provider catches up, the shell scripts get deleted"
- "Same code. Same runtime. Same agent. One line changed the boundary."
- "Not prompt engineering — actual enforcement at the infrastructure level"
- "Deploying agents is an infrastructure problem, not just a code problem"
- "We're paving the road while driving on it"
- "Boring and standard — that's the aspiration"

### The Three Provider Gaps (Numbered for Clarity)

1. **Gateway targets** — missing `grantType` (OAuth). Workaround: CLI script
   in `null_resource`.
2. **Policy engine** — no TF resource. Workaround: CLI script in `null_resource`.
3. **Gateway drift** — `description` + `protocol_configuration` not read back.
   Workaround: `ignore_changes`.

### Transition Lines Between Sections

- Intro → Problem: "And that's the problem."
- Baseline → Agents: "Then agents showed up — and none of that mapped."
- Problem → Solution: "So I decided to pick one approach and document everything."
- Theory → Demo: "Let me show you this running."
- Demo → Questions: "So we have a working approach. But is it *the* approach?"
- Questions → Close: "The decisions teams make today become the patterns everyone else copies in two years."

---

## Anti-Patterns to Avoid

1. **Don't sell AgentCore.** You're a practitioner, not a product manager.
   Be candid about gaps. Credibility comes from honesty.

2. **Don't bash the CLI/starter toolkit.** They serve their purpose. Your
   argument is about what *production teams* need.

3. **Don't get lost in code.** Reference the repo, say "here's what the
   code does," but don't recite Terraform blocks on a podcast.

4. **Don't overuse "non-deterministic."** Say it once to set the frame,
   then switch to concrete examples. "The agent might call three tools
   or twelve" is more vivid.

5. **Don't skip the war stories.** The `_CODE_VERSION` trick, the silent
   `grantType` drop, the Cedar demo — these prove you built this, not
   just designed it.

6. **Don't predict timelines confidently.** "18 months" is fine as rough.
   Don't say "by Q3 2027 every team will..." — you'll date yourself.
