# 🏰 Drawbridge

**Azure DevOps toolkit for deploying secure web applications with Tailscale-powered private networking.**

Deploy a FastAPI + HTMX web app on Azure App Service with Azure SQL, Storage, and Key Vault — all secured behind private endpoints and accessible to your team via Tailscale. Full bring-up and tear-down in minutes using `az` CLI scripts.

## Architecture

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

**What you get:**
- Public web app secured by Entra ID (Azure AD) authentication
- All backend services (SQL, Storage, Key Vault) accessible only via private endpoints
- Developer access to private backend through Tailscale (~$4/mo for the subnet router VM)
- No Azure Bastion needed (~$140/mo saved)
- No VPN Gateway needed (~$30–140/mo saved)
- Full environment for ~$20/mo

## Quick Start

```bash
# 1. Clone and initialize
git clone https://github.com/troyscott/drawbridge.git
cd drawbridge
make init          # Creates .env from template

# 2. Configure
# Edit .env with your Azure subscription ID and Tailscale auth key

# 3. Validate and deploy
make validate      # Check prerequisites
make up            # Bring up entire environment (~10-15 min)

# 4. Check status
make status        # Show all resource states

# 5. Tear down when done
make down          # Remove everything
```

## Prerequisites

| Tool | Install |
|------|---------|
| [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-macos) | `brew install azure-cli` |
| [jq](https://stedolan.github.io/jq/) | `brew install jq` |
| [Tailscale](https://tailscale.com/download) | `brew install tailscale` |
| Azure Subscription | [Free account](https://azure.microsoft.com/free/) |
| Tailscale Account | [Free tier](https://login.tailscale.com/start) (3 users, 100 devices) |

## Project Structure

```
drawbridge/
├── scripts/                    # az CLI infrastructure scripts
│   ├── config.sh               # Central configuration (sourced by all scripts)
│   ├── up.sh                   # Orchestrator: bring everything up
│   ├── down.sh                 # Orchestrator: tear everything down
│   └── status.sh               # Show resource status
├── app/                        # FastAPI + HTMX application (v0.2.0)
├── docs/                       # Architecture docs and runbooks
├── .env.template               # Environment config template
├── Makefile                    # Developer convenience targets
├── LICENSE                     # MIT
└── README.md
```

## Make Targets

```
make help          Show all available targets
make init          Create .env from template
make validate      Check prerequisites and config
make config        Print current configuration
make up            Bring up entire environment
make down          Tear down entire environment
make status        Show resource status
make deploy        Deploy application code
make logs          Stream App Service logs
```

## Cost Breakdown (Dev Environment)

| Resource | SKU | Est. Monthly |
|----------|-----|-------------|
| App Service Plan | B1 Linux | ~$13 |
| Azure SQL Database | Serverless 2vCore, auto-pause | ~$5 |
| Storage Account | Standard LRS | ~$1 |
| Key Vault | Standard | ~$0 |
| Tailscale VM | Standard_B1s | ~$4 |
| Application Insights | Workspace-based | ~$0 |
| Private Endpoints (×3) | — | ~$3 |
| **Total** | | **~$26/mo** |

## Roadmap

- [x] **v0.1.0** — MVP: Infrastructure scripts with Tailscale integration
- [ ] **v0.2.0** — FastAPI + HTMX application with Entra ID auth
- [ ] **v0.3.0** — Bicep/Terraform IaC templates, CI/CD pipeline
- [ ] **v1.0.0** — Multi-environment support, production hardening

See the [project board](https://github.com/users/troyscott/projects/7) for detailed progress.

## Contributing

Contributions welcome! See the [issues](https://github.com/troyscott/drawbridge/issues) for open tasks. Issues labeled `good first issue` are a great starting point.

## License

[MIT](LICENSE)
