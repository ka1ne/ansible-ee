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

## Quick Start

```bash
# Build EE image
make build

# Lint
make lint

# Scan image + collections
make scan

# Generate SBOM
make sbom

# Dry run against dev
make test-dry-run

# Push to registry
make push
```

## Pipeline Usage

The EE image is consumed as a Container Step in Harness pipelines.
The React manifest generator produces a YAML file which is passed as `--extra-vars`
to `ansible-playbook`. See `examples/manifest-example.yml` for the expected format.

```bash
ansible-playbook playbooks/site.yml \
  -i inventory/dev.yml \
  -e @manifest.yml \
  --limit "dev-win-01.internal.bank"
```

## Security

- All Galaxy collections pulled from internal mirror only (no public egress)
- Python + system deps pinned to exact versions
- EE image scanned with Trivy, SBOM generated with Syft
- Collection Python code scanned with Bandit + Semgrep
- Image runs as non-root (UID 1000)
- Credentials injected at runtime via environment variables, never baked into image
