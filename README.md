# Ansible Execution Environment

Containerised Ansible control node for application deployment and migration.

## Structure

```
├── execution-environment.yml   # EE build definition (ansible-builder)
├── requirements.yml            # Galaxy collections (pinned, internal mirror)
├── requirements.txt            # Python dependencies (pinned)
├── bindep.txt                  # System packages
├── ansible.cfg                 # Hardened Ansible config
├── Makefile                    # Build/scan/test commands
│
├── playbooks/
│   └── site.yml                # Main entrypoint — manifest-driven role dispatch
│
├── roles/                      # Internal roles (or pulled via collections)
│
├── inventory/
│   ├── dev.yml
│   ├── staging.yml
│   └── prod.yml
│
├── group_vars/
│   └── windows.yml             # WinRM connection vars (creds from env)
│
├── schemas/
│   └── manifest-schema.json    # JSON Schema for manifest validation
│
├── scripts/
│   ├── scan-collections.sh     # Security scan for Galaxy collection contents
│   └── validate-manifest.py    # Manifest schema validation
│
└── examples/
    └── manifest-example.yml    # Sample manifest (React app output)
```

## Getting Started

### Prerequisites

| Tool | Min version |
|------|-------------|
| Python | 3.11 |
| Podman | 4.x |
| Git | any |

### First-time setup

```bash
cp .env.example .env
$EDITOR .env          # set IMAGE_NAME at minimum; add mirror vars for air-gapped CI

make bootstrap        # verify prereqs + create .venv
make test-bootstrap   # confirm all tools importable
```

### Common tasks

```bash
make build              # Build the EE image
make lint               # ansible-lint + yamllint
make test-syntax        # Playbook syntax check
make scan               # Trivy + collection security scan
make test-dry-run       # --check --diff against dev inventory
make push               # Tag and push to registry

# Molecule — smoke test (Windows Server 2019 via Podman/KVM)
make test-molecule-init

# Molecule — full SQL Server role test (requires a live host)
MOLECULE_TEST_HOST=<host> ANSIBLE_WINRM_USER=<u> ANSIBLE_WINRM_PASSWORD=<p> \
  make test-molecule-mssql

make help               # List all targets
```

## AWX (local dev)

AWX runs on k3s via the AWX Operator (`awx/awx-instance.yml`).

```bash
make awx-operator   # install operator
make awx-install    # deploy AWX (~5 min)
make awx-status     # get pod status + admin password
# create an API token: Settings → Users → admin → Tokens → Add → set AWX_TOKEN=<token> in .env
make awx-sync-ee    # register/update the EE definition
```

The Harness `ee-build` pipeline runs `awx/register-ee.sh` automatically after every successful build.

## Pipeline Usage

The EE image is consumed as a Container Step in Harness pipelines.
The React manifest generator produces a YAML file which is passed as `--extra-vars`
to `ansible-playbook`. See `examples/manifest-example.yml` for the expected format.

```bash
ansible-playbook playbooks/site.yml \
  -i inventory/dev.yml \
  -e @manifest.yml \
  --limit "dev-win-01.ka1ne.dev"
```

## Security

- All Galaxy collections pulled from internal mirror only (no public egress)
- Python + system deps pinned to exact versions
- EE image scanned with Trivy, SBOM generated with Syft
- Collection Python code scanned with Bandit + Semgrep
- Image runs as non-root (UID 1000)
- Credentials injected at runtime via environment variables, never baked into image
