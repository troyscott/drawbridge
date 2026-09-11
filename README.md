# 🏰 Drawbridge

**A cookbook toolkit for standing up (and tearing down) secure Azure Web App architectures for POCs.**

Each **cookbook** under `cookbooks/` is a self-contained `az` CLI recipe for a different architecture — bring it up in minutes, try it out, and tear it down completely when you're done. Pick the cookbook that matches the pattern you're testing.

## Cookbooks

### `dmz-app-sql` — public App Service, private backend

Deploy a FastAPI + HTMX web app on Azure App Service with Azure SQL, Storage, and Key Vault — all secured behind private endpoints and accessible to your team via Tailscale.

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
- No Azure Bastion needed (~$140/mo saved), no VPN Gateway needed (~$30–140/mo saved)

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

### `simple-app-easyauth` — bare App Service + Entra ID

The minimal end of the spectrum: a single public App Service with Entra ID (Easy Auth v2) authentication. No VNet, no private backend, no Tailscale — just enough to test an app registration or Easy Auth flow.

| Resource | SKU | Est. Monthly |
|----------|-----|-------------|
| App Service Plan | B1 Linux | ~$13 |
| **Total** | | **~$13/mo** |

## Quick Start

```bash
# 1. Clone and initialize
git clone https://github.com/troyscott/drawbridge.git
cd drawbridge
make init                            # Creates .env from template (shared across cookbooks)

# 2. Configure
# Edit .env with your Azure subscription ID (+ Tailscale auth key for dmz-app-sql)

# 3. Pick a cookbook, validate, and deploy
make list-cookbooks
make validate COOKBOOK=dmz-app-sql   # Check prerequisites
make up COOKBOOK=dmz-app-sql         # Bring up that cookbook (~10-15 min)

# 4. Check status
make status COOKBOOK=dmz-app-sql

# 5. Tear down when done
make down COOKBOOK=dmz-app-sql
```

## Prerequisites

| Tool | Install |
|------|---------|
| [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-macos) | `brew install azure-cli` |
| [jq](https://stedolan.github.io/jq/) | `brew install jq` |
| [Tailscale](https://tailscale.com/download) | `brew install tailscale` (only needed for `dmz-app-sql`) |
| Azure Subscription | [Free account](https://azure.microsoft.com/free/) |
| Tailscale Account | [Free tier](https://login.tailscale.com/start) (3 users, 100 devices) |

macOS/Linux with bash — no Windows/PowerShell support currently.

## Project Structure

```
drawbridge/
├── lib/
│   └── common.sh                 # Shared helpers (log_*, check_prerequisites, resource_group_exists, run_az)
├── cookbooks/
│   ├── dmz-app-sql/               # Public App Service + private SQL/Storage/KeyVault + Tailscale
│   │   ├── config.sh              # Resource naming for this cookbook (sources lib/common.sh)
│   │   ├── up.sh / down.sh / status.sh
│   │   └── create-*.sh / delete-*.sh  # One idempotent pair per resource type
│   └── simple-app-easyauth/       # Bare App Service + Entra ID Easy Auth
│       ├── config.sh
│       ├── up.sh / down.sh / status.sh
│       └── create-appservice.sh / delete-appservice.sh
├── app/                            # FastAPI + HTMX application (future — v0.2.0)
├── docs/                           # Architecture docs and runbooks
├── .env.template                   # Shared environment config template
├── Makefile                        # Cookbook-aware developer targets
├── LICENSE                         # MIT
└── README.md
```

Each cookbook hardcodes its own `PROJECT` name in `config.sh` (`drawbridge-dmz`, `drawbridge-simple`, ...) so resource names never collide even if multiple cookbooks are deployed to the same subscription at once. Shared settings (`AZURE_SUBSCRIPTION_ID`, `AZURE_LOCATION`, `ENV`) come from the single root `.env`.

## Make Targets

```
make help                            Show all available targets
make init                            Create .env from template
make list-cookbooks                  List available cookbooks
make validate COOKBOOK=<name>        Check prerequisites and print config
make config COOKBOOK=<name>          Print resolved configuration
make up COOKBOOK=<name>              Bring up a cookbook's environment
make down COOKBOOK=<name>            Tear down a cookbook's environment
make status COOKBOOK=<name>          Show resource status
make deploy COOKBOOK=<name>          Deploy application code
make logs COOKBOOK=<name>            Stream App Service logs
```

## Adding a new cookbook

1. Create `cookbooks/<name>/`.
2. Write `config.sh`: source `../../lib/common.sh`, load `.env`, hardcode a unique `PROJECT`, define resource names, and a `print_config` function.
3. Write one `create-<resource>.sh`/`delete-<resource>.sh` pair per resource — idempotent (check-before-create, check-before-delete), following the pattern in `cookbooks/dmz-app-sql/`.
4. Write `up.sh` (orchestrates the create scripts, with a confirmation prompt), `down.sh` (orchestrates delete scripts, with a confirmation prompt or `--force`), and `status.sh`.
5. `make list-cookbooks` will pick it up automatically — no Makefile changes needed.

## Roadmap

- [x] **v0.1.0** — MVP: `dmz-app-sql` infrastructure scripts with Tailscale integration
- [x] **v0.2.0** — Cookbook framework + `simple-app-easyauth` cookbook
- [ ] **v0.3.0** — FastAPI + HTMX application with Entra ID auth
- [ ] **v0.4.0** — Bicep/Terraform IaC templates, CI/CD pipeline
- [ ] **v1.0.0** — Multi-environment support, production hardening

See the [project board](https://github.com/users/troyscott/projects/7) for detailed progress.

## Contributing

Contributions welcome! See the [issues](https://github.com/troyscott/drawbridge/issues) for open tasks. Issues labeled `good first issue` are a great starting point.

## License

[MIT](LICENSE)
