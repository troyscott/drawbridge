# Drawbridge — Project Specification

> **Purpose:** This document is the single source of truth for anyone (human or AI agent) picking up this project. It captures architecture decisions, conventions, current state, and how to continue development.

## 1. Project Overview

**Drawbridge** is an open-source **cookbook toolkit**: a `cookbooks/<name>/` convention plus a shared helper library for standing up and tearing down different secure Azure Web App architectures for POCs. Each cookbook is a self-contained `az` CLI recipe — pick the one that matches the architecture you're testing.

- **Repo:** https://github.com/troyscott/drawbridge
- **Project Board:** https://github.com/users/troyscott/projects/7
- **License:** MIT

### What it does
- Provides a growing set of **cookbooks**, each a complete, idempotent bring-up/tear-down recipe for one architecture
- `dmz-app-sql`: FastAPI + HTMX web app on Azure App Service with Azure SQL, Storage, and Key Vault behind private endpoints, with a Tailscale subnet router for developer access. Replaces Azure Bastion (~$140/mo) and VPN Gateway (~$30-140/mo) with Tailscale (~$4/mo).
- `simple-app-easyauth`: a bare App Service with Entra ID (Easy Auth v2) — no networking — for testing an app registration or auth flow in isolation.
- Full bring-up/tear-down per cookbook via `az` CLI shell scripts and `make <target> COOKBOOK=<name>`
- A shared `lib/common.sh` (logging, prerequisite checks, resource-group checks) so new cookbooks don't reinvent it

### Target audience
- Small dev teams (1-3 people) on Azure running architecture POCs
- Developers who want to compare network-isolation patterns without hand-building each one
- Teams that prefer shell scripts over heavy IaC frameworks for initial setup

## 2. Architecture

### Cookbook: `dmz-app-sql` — Public App + Private Backend
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

### Cookbook: `simple-app-easyauth` — Bare App Service

A single public App Service with Entra ID (Easy Auth v2). No VNet, no private backend, no Tailscale. For testing an app registration or Easy Auth flow without the networking overhead.

### Future cookbook idea: Fully Private (future — issue #16)
- `dmz-app-sql`, but the App Service is also behind a private endpoint (no public URL)
- VNet expanded to /23 for optional AzureBastionSubnet
- App only accessible via Tailscale
- Config toggle: `NETWORK_MODE=public|private`

### Cost (dmz-app-sql, Dev Environment)
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

All Azure resources follow: `{resource-prefix}-{project}-{env}[-{suffix}]`, where `{project}` is **hardcoded per cookbook** (e.g. `drawbridge-dmz`, `drawbridge-simple`) rather than read from the shared `.env` — this guarantees two cookbooks never collide on the same resource group or names when both are deployed to the same subscription.

| Resource | Pattern | Example (`dmz-app-sql`) |
|---|---|---|
| Resource Group | `rg-{project}-{env}-{region}` | `rg-drawbridge-dmz-dev-eastus2` |
| VNet | `vnet-{project}-{env}` | `vnet-drawbridge-dmz-dev` |
| Subnet | `snet-{purpose}` | `snet-app`, `snet-pe`, `snet-ts` |
| App Service Plan | `asp-{project}-{env}` | `asp-drawbridge-dmz-dev` |
| Web App | `app-{project}-{env}` | `app-drawbridge-dmz-dev` |
| SQL Server | `sql-{project}-{env}` | `sql-drawbridge-dmz-dev` |
| SQL Database | `sqldb-{project}-{env}` | `sqldb-drawbridge-dmz-dev` |
| Storage | `st{project-no-dashes}{env}{random}` | `stdrawbridgedmzdev1a2b3c` |
| Key Vault | `kv-{project}-{env}-{random}` | `kv-drawbridge-dmz-dev-1a2b3c` |
| Private Endpoint | `pe-{service}-{project}-{env}` | `pe-sql-drawbridge-dmz-dev` |
| Tailscale VM | `vm-{project}-ts-{env}` | `vm-drawbridge-dmz-ts-dev` |
| App Insights | `appi-{project}-{env}` | `appi-drawbridge-dmz-dev` |
| Log Analytics | `law-{project}-{env}` | `law-drawbridge-dmz-dev` |
| Entra App | `app-{project}-{env}-auth` | `app-drawbridge-dmz-dev-auth` |

Storage account names strip dashes from `{project}` since Azure Storage names must be lowercase alphanumeric only. All names are derived from variables in each cookbook's `config.sh`; shared helpers live in `lib/common.sh`. The `{random}` suffix is a 6-char hash of the subscription ID for globally unique names.

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
├── lib/
│   └── common.sh                  # Shared: log_*, check_prerequisites, resource_group_exists, run_az
├── cookbooks/
│   ├── dmz-app-sql/                # Public App Service + private SQL/Storage/KeyVault + Tailscale
│   │   ├── config.sh               # Cookbook config (PROJECT=drawbridge-dmz, sources lib/common.sh)
│   │   ├── up.sh / down.sh / status.sh
│   │   ├── create-network.sh / delete-network.sh                 [issue #2 ✅]
│   │   ├── create-tailscale.sh / delete-tailscale.sh             [issue #3 ✅]
│   │   ├── create-appservice.sh / delete-appservice.sh           [issue #4 ✅]
│   │   ├── create-sql.sh / delete-sql.sh                         [issue #5 ✅]
│   │   ├── create-storage.sh / delete-storage.sh                 [issue #6 ✅]
│   │   ├── create-private-endpoints.sh / delete-private-endpoints.sh [issue #7 ✅]
│   │   └── create-monitoring.sh / delete-monitoring.sh           [issue #8 ✅]
│   └── simple-app-easyauth/        # Bare App Service + Entra ID Easy Auth
│       ├── config.sh               # Cookbook config (PROJECT=drawbridge-simple)
│       ├── up.sh / down.sh / status.sh
│       └── create-appservice.sh / delete-appservice.sh
├── app/                           # FastAPI + HTMX app [v0.3.0]
├── docs/
│   └── SPEC.md                    # ← This file
├── .env.template                  # Shared environment variables template
├── .gitignore
├── Makefile                       # cookbook-aware: make <target> COOKBOOK=<name>
├── LICENSE                        # MIT
└── README.md
```

## 8. Development Workflow

### For contributors
```bash
git clone https://github.com/troyscott/drawbridge.git
cd drawbridge
make init                              # Copy .env.template → .env
# Edit .env with Azure subscription ID + Tailscale auth key
make list-cookbooks                    # See available recipes
make validate COOKBOOK=dmz-app-sql     # Check prerequisites
make up COOKBOOK=dmz-app-sql           # Deploy that cookbook (~10-15 min)
make status COOKBOOK=dmz-app-sql       # Verify resources
make down COOKBOOK=dmz-app-sql         # Tear down when done
```

### Branch strategy
- `main` — stable, all PRs merge here via squash
- `feature/{issue#}-{short-name}` — feature branches tied to issues
- `docs/{topic}` — documentation changes
- All commits reference the GitHub issue: `Closes #N`
- Co-author line: `Co-Authored-By: Oz <oz-agent@warp.dev>`

### Script conventions
- All scripts source their cookbook's `config.sh` as their first action; `config.sh` sources `lib/common.sh`
- All scripts are **idempotent** — check before creating
- All create scripts have a matching delete script
- Use `log_info`, `log_success`, `log_warn`, `log_error` from `lib/common.sh`
- Print a summary section at the end of each script
- Use `--output none` on az commands to suppress JSON noise
- A cookbook's `PROJECT` is hardcoded in its own `config.sh`, never read from `.env` (prevents cross-cookbook name collisions)

## 9. Current Progress

### Completed (closed issues)
- #1 ✅ Project scaffolding and config system
- #2 ✅ Resource Group and VNet provisioning script
- #3 ✅ Tailscale subnet router VM provisioning
- #4 ✅ App Service provisioning (VNet integration + Entra ID auth)
- #5 ✅ Azure SQL Database provisioning script
- #6 ✅ Storage account and Key Vault provisioning
- #7 ✅ Private endpoints for SQL, Storage, Key Vault
- #8 ✅ Application Insights provisioning
- #9 ✅ Bring-up / tear-down orchestrator scripts
- #10 ✅ README and architecture documentation

### v0.2.0 — Cookbook framework (this change)
- Extracted shared helpers into `lib/common.sh`
- Relocated the MVP architecture into `cookbooks/dmz-app-sql/` unchanged
- Added `cookbooks/simple-app-easyauth/` — a bare App Service + Entra Easy Auth cookbook
- Made the Makefile cookbook-aware (`make <target> COOKBOOK=<name>`, `make list-cookbooks`)
- Fixed a latent naming bug: storage account names now strip dashes from `{project}` (needed once `PROJECT` became `drawbridge-dmz`/`drawbridge-simple`)
- No open GitHub issue tracks this yet — file one before starting further cookbook work

### Future milestones
- **v0.3.0 — App Foundation:** #11 FastAPI skeleton, #12 Entra auth in-app, #13 DB models, #14 App Insights SDK
- **v0.4.0 — IaC Templates:** #15 Bicep, #16 Full private VNet option, #17 GitHub Actions CI/CD
- **v1.0.0 — Production Ready:** #18 Multi-env, #19 Cost calculator, #20 Contributor guide
- Windows/PowerShell support: explicitly deferred, revisit only if actually needed

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
| Multi-architecture support | `cookbooks/<name>/` convention + shared `lib/common.sh` | Needed once a second architecture (`simple-app-easyauth`) came up; avoids re-forking the whole repo per architecture |
| Cross-cookbook naming | Each cookbook hardcodes its own `PROJECT` | Prevents resource-name collisions if two cookbooks are deployed to the same subscription at once |

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
