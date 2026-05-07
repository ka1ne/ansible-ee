# Ansible EE — Tekton PoC

Builds and runs an Ansible Execution Environment (EE) image through a Tekton pipeline.
Proves the full cycle: **build EE image → push to registry → run WinRM + SQL Server probe**.

## What it proves

At the end of a successful PipelineRun the logs confirm:

| Check | What it validates |
|---|---|
| WinRM ping | EE container can reach the Windows host |
| Host facts | OS hostname + version gathered |
| TCP 1433 | Windows host can reach SQL Server on port 1433 |
| SQL login | `SELECT @@VERSION` via `sqlcmd` (skipped if `sqlcmd` not on host) |

## Prerequisites

- OpenShift cluster with **OpenShift Pipelines** (Tekton) installed
- Windows host with WinRM enabled on port 5985 (NTLM/HTTP — PoC only)
- SQL Server accessible on port 1433 from the Windows host
- Container registry accessible from the cluster

## One-time setup

### 1. Enable WinRM on the Windows host

Run as Administrator on the Windows host:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process -Force
.\poc\scripts\setup-winrm-local.ps1
```

### 2. Create the credentials secret

```bash
kubectl create secret generic winrm-credentials \
  --from-literal=host=<windows-host-ip> \
  --from-literal=username=ansible-poc \
  --from-literal=password=<winrm-password> \
  --from-literal=mssql_host=<mssql-host-ip> \
  --from-literal=mssql_sa_password=<sa-password> \
  -n <your-namespace>
```

### 3. Apply Tekton manifests

```bash
# Edit tekton/pipelinerun.yml — set GIT_URL and IMAGE first
make tekton-apply NAMESPACE=<your-namespace>
```

## Run the pipeline

```bash
make tekton-run NAMESPACE=<your-namespace>
```

Watch the run:

```bash
kubectl get pipelineruns -n <your-namespace> -w
tkn pipelinerun logs -f -n <your-namespace>
```

## Run locally (without Tekton)

Requires Podman Desktop + WSL2. Copy and fill in `poc/.env.example`:

```bash
cp poc/.env.example poc/.env
make poc-local
```

## Repo structure

```
.
├── Dockerfile              # EE image — runtime only (no playbooks baked in)
├── requirements.txt        # Python: pywinrm, requests-ntlm, jmespath
├── requirements.yml        # Ansible: ansible.windows collection only
├── ansible.cfg             # Minimal config
├── Makefile                # build / poc-local / tekton-apply / tekton-run / clean
├── tekton/
│   ├── task-git-clone.yml  # Clone source repo into workspace
│   ├── task-build-ee.yml   # Build + push EE image (buildah)
│   ├── task-run-poc.yml    # Run winrm-poc.yml inside the EE
│   ├── pipeline.yml        # Pipeline: clone → build → run
│   └── pipelinerun.yml     # Sample trigger (edit GIT_URL + IMAGE before applying)
└── poc/
    ├── .env.example
    ├── inventory/poc-local.yml   # WINRM_HOST from env, falls back to host.containers.internal
    ├── playbooks/winrm-poc.yml   # 5-stage probe: ping, facts, port check, SQL login, summary
    └── scripts/
        ├── run-poc.sh            # Local orchestration (Podman + MSSQL + EE)
        └── setup-winrm-local.ps1 # One-time WinRM enablement (run as Administrator)
```
