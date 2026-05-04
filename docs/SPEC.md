# Drawbridge — Project Specification

> **Purpose:** This document is the single source of truth for anyone (human or AI agent) picking up this project. It captures architecture decisions, conventions, current state, and how to continue development.

## 1. Project Overview

**Drawbridge** is an open-source Azure DevOps toolkit that deploys a secure web application with Tailscale-powered private networking. It targets small dev shops that need enterprise-grade network isolation without enterprise-grade costs.

- **Repo:** https://github.com/troyscott/drawbridge
- **Project Board:** https://github.com/users/troyscott/projects/7
- **License:** MIT

### What it does
- Deploys a FastAPI + HTMX web app on Azure App Service
- Secures backend services (SQL, Storage, Key Vault) behind private endpoints
- Uses a Tailscale subnet router for developer access to the private backend
- Full bring-up/tear-down via `az` CLI shell scripts and `make` targets
- Replaces Azure Bastion (~$140/mo) and VPN Gateway (~$30-140/mo) with Tailscale (~$4/mo)

### Target audience
- Small dev teams (1-3 people) on Azure
- Developers who want private networking without the complexity
- Teams that prefer shell scripts over heavy IaC frameworks for initial setup

## 2. Architecture

### Option A: Public App + Private Backend (MVP — current focus)
```
┌──────────────────────────────────────────────────────┐
│  Azure VNet  10.50.0.0/24                            │
│                                                      │
│  snet-app /26 ─── App Service (public + Entra ID)    │
│                     │ outbound VNet integration       │
│  snet-pe  /26 ─── Private Endpoints                  │
│                     ├── Azure SQL                     │
│                     ├── Storage Account               │
│                     └── Key Vault                     │
│                     ▲                                 │
│  snet-ts  /26 ─── Tailscale Subnet Router (B1s VM)   │
│                     │ advertises 10.50.0.0/24         │
└─────────────────────┼────────────────────────────────┘
                      │ WireGuard tunnel
                      ▼
              ┌───────────────┐
              │   Tailnet     │
              │  (free tier)  │
              └───┬───────┬───┘
                  │       │
               Dev Mac  Dev Mac
```

- App Service has a public URL secured by Entra ID (Easy Auth v2)
- All backend services accessible only via private endpoints in the VNet
- Tailscale subnet router VM advertises the VNet CIDR to the tailnet
- Developers on the tailnet can access private endpoints directly (SQL, Storage, KV)

### Option B: Fully Private (future — issue #16)
- App Service also behind a private endpoint (no public URL)
- VNet expanded to /23 for optional AzureBastionSubnet
- App only accessible via Tailscale
- Config toggle: `NETWORK_MODE=public|private`

### Cost (Dev Environment)
| Resource | SKU | Monthly |
|---|---|---|
| App Service Plan | B1 Linux | ~$13 |
| Azure SQL | Serverless 2vCore, auto-pause 60min | ~$5 |
| Storage Account | Standard LRS | ~$1 |
| Key Vault | Standard, RBAC | ~$0 |
| Tailscale VM | Standard_B1s, auto-shutdown 23:00 | ~$4 |
| Application Insights | Workspace-based | ~$0 |
| Private Endpoints ×3 | | ~$3 |
| **Total** | | **~$26/mo** |

## 3. Tech Stack

| Layer | Technology | Notes |
|---|---|---|
| Web framework | FastAPI | ASGI, async-native |
| Frontend | HTMX + Jinja2 | Server-rendered, no JS framework |
| CSS | Pico CSS or Tailwind | Lightweight, decision deferred to #11 |
| ORM | SQLModel | FastAPI-native (Pydantic + SQLAlchemy) |
| Database | Azure SQL Serverless | Entra-only auth, managed identity |
| Storage | Azure Blob (Standard LRS) | Private endpoint only |
| Secrets | Azure Key Vault (RBAC) | Private endpoint only |
| Auth | Entra ID via Easy Auth v2 | Single-tenant, app registration |
| Monitoring | Application Insights | OpenTelemetry-based SDK |
| VPN | Tailscale (free tier) | Subnet router on B1s VM |
| Infra scripts | Bash + `az` CLI | Idempotent, Makefile orchestration |
| IaC (future) | Bicep | Generated from proven CLI scripts |
| CI/CD (future) | GitHub Actions | OIDC auth to Azure |
| Python env | micromamba | User preference for local dev |

## 4. Naming Conventions

All Azure resources follow: `{resource-prefix}-{project}-{env}[-{suffix}]`

| Resource | Pattern | Example |
|---|---|---|
| Resource Group | `rg-{project}-{env}-{region}` | `rg-drawbridge-dev-eastus2` |
| VNet | `vnet-{project}-{env}` | `vnet-drawbridge-dev` |
| Subnet | `snet-{purpose}` | `snet-app`, `snet-pe`, `snet-ts` |
| App Service Plan | `asp-{project}-{env}` | `asp-drawbridge-dev` |
| Web App | `app-{project}-{env}` | `app-drawbridge-dev` |
| SQL Server | `sql-{project}-{env}` | `sql-drawbridge-dev` |
| SQL Database | `sqldb-{project}-{env}` | `sqldb-drawbridge-dev` |
| Storage | `st{project}{env}{random}` | `stdrawbridgedev1a2b3c` |
| Key Vault | `kv-{project}-{env}-{random}` | `kv-drawbridge-dev-1a2b3c` |
| Private Endpoint | `pe-{service}-{project}-{env}` | `pe-sql-drawbridge-dev` |
| Tailscale VM | `vm-{project}-ts-{env}` | `vm-drawbridge-ts-dev` |
| App Insights | `appi-{project}-{env}` | `appi-drawbridge-dev` |
| Log Analytics | `law-{project}-{env}` | `law-drawbridge-dev` |
| Entra App | `app-{project}-{env}-auth` | `app-drawbridge-dev-auth` |

All names are derived from variables in `scripts/config.sh`. The `{random}` suffix is a 6-char hash of the subscription ID for globally unique names.

## 5. Network Design

| Subnet | CIDR | Purpose | Special Config |
|---|---|---|---|
| `snet-app` | 10.50.0.0/26 | App Service VNet integration | Delegated to `Microsoft.Web/serverFarms` |
| `snet-pe` | 10.50.0.64/26 | Private endpoints | Private endpoint network policies disabled |
| `snet-ts` | 10.50.0.128/26 | Tailscale subnet router VM | Plain subnet |
| (reserved) | 10.50.0.192/26 | Future use / Bastion | — |

VNet integration setting `WEBSITE_VNET_ROUTE_ALL=1` ensures App Service outbound traffic (including DNS) routes through the VNet for private endpoint resolution.

## 6. Security Model

- **App Service:** Public URL with Entra ID Easy Auth (all requests must authenticate)
- **Azure SQL:** Entra-only auth (no SQL passwords), public access disabled
- **Storage:** Private endpoint only, App Service MI has Storage Blob Data Contributor
- **Key Vault:** RBAC mode, private endpoint only, App Service MI has Key Vault Secrets User
- **Tailscale VM:** No public IP, outbound-only NSG, NIC IP forwarding for routing
- **Secrets:** `.env` file (gitignored), never committed; Tailscale auth key via temp cloud-init file deleted after VM creation

## 7. Repository Structure

```
drawbridge/
├── scripts/                       # az CLI infrastructure scripts
│   ├── config.sh                  # Central config (sourced by all scripts)
│   ├── up.sh                      # Orchestrator: bring everything up
│   ├── down.sh                    # Orchestrator: tear everything down
│   ├── status.sh                  # Show resource status
│   ├── create-network.sh          # RG + VNet + subnets        [issue #2 ✅]
│   ├── delete-network.sh          # Reverse teardown            [issue #2 ✅]
│   ├── create-tailscale.sh        # Tailscale subnet router VM  [issue #3 ✅]
│   ├── delete-tailscale.sh        # VM + NIC + NSG teardown     [issue #3 ✅]
│   ├── create-appservice.sh       # ASP + Web App + Entra auth  [issue #4 ✅]
│   ├── delete-appservice.sh       # App + Plan + Entra cleanup  [issue #4 ✅]
│   ├── create-sql.sh              # [issue #5 — not yet]
│   ├── create-storage.sh          # [issue #6 — not yet]
│   ├── create-private-endpoints.sh # [issue #7 — not yet]
│   └── create-monitoring.sh       # [issue #8 — not yet]
├── app/                           # FastAPI + HTMX app [v0.2.0]
├── docs/
│   └── SPEC.md                    # ← This file
├── .env.template                  # Environment variables template
├── .gitignore
├── Makefile                       # make up/down/status/validate/help
├── LICENSE                        # MIT
└── README.md
```

## 8. Development Workflow

### For contributors
```bash
git clone https://github.com/troyscott/drawbridge.git
cd drawbridge
make init              # Copy .env.template → .env
# Edit .env with Azure subscription ID + Tailscale auth key
make validate          # Check prerequisites
make up                # Deploy everything (~10-15 min)
make status            # Verify resources
make down              # Tear down when done
```

### Branch strategy
- `main` — stable, all PRs merge here via squash
- `feature/{issue#}-{short-name}` — feature branches tied to issues
- `docs/{topic}` — documentation changes
- All commits reference the GitHub issue: `Closes #N`
- Co-author line: `Co-Authored-By: Oz <oz-agent@warp.dev>`

### Script conventions
- All scripts source `config.sh` as their first action
- All scripts are **idempotent** — check before creating
- All create scripts have a matching delete script
- Use `log_info`, `log_success`, `log_warn`, `log_error` from config.sh
- Print a summary section at the end of each script
- Use `--output none` on az commands to suppress JSON noise

## 9. Current Progress

### Completed (closed issues)
- #1 ✅ Project scaffolding and config system
- #2 ✅ Resource Group and VNet provisioning script
- #3 ✅ Tailscale subnet router VM provisioning
- #4 ✅ App Service provisioning (VNet integration + Entra ID auth)

### Remaining MVP (v0.1.0) — open issues
- #5 Azure SQL Database provisioning script
- #6 Storage account and Key Vault provisioning
- #7 Private endpoints for SQL, Storage, Key Vault
- #8 Application Insights provisioning
- #9 Bring-up / tear-down orchestrator scripts (stubs exist, need wiring)
- #10 README and architecture documentation (README exists, needs polish)

### Future milestones
- **v0.2.0 — App Foundation:** #11 FastAPI skeleton, #12 Entra auth in-app, #13 DB models, #14 App Insights SDK
- **v0.3.0 — IaC Templates:** #15 Bicep, #16 Full private VNet option, #17 GitHub Actions CI/CD
- **v1.0.0 — Production Ready:** #18 Multi-env, #19 Cost calculator, #20 Contributor guide

## 10. Key Decisions Log

| Decision | Choice | Rationale |
|---|---|---|
| Infra tool | `az` CLI scripts first | Prove the architecture before codifying in Bicep/Terraform |
| VPN approach | Tailscale (free tier) | $4/mo vs $140+ for Bastion; works with 3 users, 100 devices |
| App framework | FastAPI + HTMX | Modern Python, server-rendered (no SPA complexity) |
| Database | Azure SQL Serverless | Auto-pause saves money in dev; Entra-only auth = no passwords |
| Auth | Entra ID Easy Auth v2 | Zero app-code needed for auth; FastAPI reads injected headers |
| Storage suffix | MD5 of subscription ID | Deterministic but unique — same sub always gets same suffix |
| Tailscale VM auto-shutdown | 23:00 UTC | Saves ~40% on B1s; `up.sh` restarts if deallocated |
| Python env (local) | micromamba | User preference; documented in prereqs |
| OS target | macOS | Primary dev machine; scripts use bash (not PowerShell) |

## 11. How to Continue Development

### Picking up in a new session
1. Read this spec (`docs/SPEC.md`)
2. Check the project board: https://github.com/users/troyscott/projects/7
3. Check open issues: `gh issue list --repo troyscott/drawbridge --state open`
4. Check current branch state: `git log --oneline -5`
5. Pick the next open issue in the current milestone and follow the branch/PR workflow

### For AI agents
- The GitHub project board and issues are the task backlog
- Each issue has acceptance criteria — implement all of them
- Follow the script conventions in Section 8
- Branch naming: `feature/{issue#}-{short-name}`
- Commit messages: reference the issue with `Closes #{number}`
- Always include `Co-Authored-By: Oz <oz-agent@warp.dev>`
- Run `bash -n script.sh` to syntax-check before committing
- Create a PR with a summary of what was built and verification steps
