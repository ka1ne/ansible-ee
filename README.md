# ansible-ee — a Windows automation starter kit for AWX

A batteries-included starting point for automating Windows with AWX: a
Windows-focused Ansible Execution Environment, the AWX configuration that goes
with it, and real IIS and SQL Server content to run through it.

The intended path is that you clone this, point it at a Windows host, and get a
green connectivity probe within an hour — then replace the example content with
your own.

## What this is not

Deploying AWX and configuring AWX are solved problems, and this project does
not try to solve them again:

| For this | Use this |
|---|---|
| Installing AWX on Kubernetes | [ansible/awx-operator](https://github.com/ansible/awx-operator) |
| A local AWX lab from nothing | [kurokobo/awx-on-k3s](https://github.com/kurokobo/awx-on-k3s) |
| Driving AWX objects from git | [redhat-cop/infra.controller_configuration](https://github.com/redhat-cop/infra.controller_configuration) |

This repository is the layer on top: the image AWX runs your Windows jobs in,
the configuration that registers it, and content worth running. It uses all
three of the projects above rather than reimplementing them.

## How it fits together

```
  ee/execution-environment.yml
            │
            │  ansible-builder
            ▼
   ghcr.io/ka1ne/ansible-ee          ← the Execution Environment image
            │
            ├──────────────┬────────────────────┐
            ▼              ▼                    ▼
      make test-local     AWX              Tekton on OpenShift
      (laptop)        (job templates)      (build + probe)
            │              │                    │
            └──────────────┴────────────────────┘
                           │  WinRM
                           ▼
                    Windows hosts
                    (IIS, SQL Server)
```

One EE definition feeds all three paths. Every path calls the same `make`
targets, so what CI builds and what you build locally cannot drift apart.

## Three ways to use it

| Path | Command | Needs | Good for |
|---|---|---|---|
| Local | `make test-local` | Docker, a Windows host | Trying it out, developing content |
| AWX | `make awx-apply` | An AWX instance | How you would actually run this |
| OpenShift | `make tekton-apply` | OpenShift Pipelines | Building the EE in-cluster |

The local path is the one to start with. It proves the image, your credentials
and the network path before AWX is anywhere in the picture.

## Quickstart

Requires Python 3.11+, git, and Docker (or Podman via `CONTAINER_RT=podman`).

```bash
git clone https://github.com/ka1ne/ansible-ee.git
cd ansible-ee
make bootstrap && source .venv/bin/activate
make deps
```

Prepare a Windows host so it accepts WinRM — as Administrator on that host:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process -Force
.\dev\scripts\setup-winrm-local.ps1 -WinRMPassword '<a password you generated>'
```

Then fill in credentials and run the probe:

```bash
cp dev/.env.example .env     # set WINRM_USER, WINRM_PASSWORD, MSSQL_SA_PASSWORD
make test-local
```

That builds the EE, starts a throwaway SQL Server 2022 container, and runs the
connectivity probe. A green run proves WinRM works, facts can be gathered, the
Windows host can reach SQL Server, and a SQL login succeeds.

Details and troubleshooting are in [docs/quickstart.md](docs/quickstart.md).

## What is in here

```
ee/                  Execution Environment definition — the one build recipe
playbooks/           Entry points, starting with connectivity_probe.yml
roles/               IIS, SQL Server and .NET migration content
inventories/         local/ for the dev harness, example/ as a template
awx/                 AWX operator manifests, and configuration-as-code
ci/tekton/           OpenShift adapter over the same make targets
dev/                 Local harness: .env template and helper scripts
docs/                Longer-form documentation
```

Run `make` with no arguments to list every target.

## Status

The Execution Environment, the connectivity probe, CI and the Tekton adapter
work today. The AWX configuration-as-code layer and the hardened IIS and SQL
Server roles are in progress — see the
[open issues](https://github.com/ka1ne/ansible-ee/issues) and the milestone
labels for what is landing next.

The published image is `ghcr.io/ka1ne/ansible-ee`, tagged `latest` from `main`
and by short SHA for every build.

## Documentation

- [Quickstart](docs/quickstart.md) — the local path, end to end
- [Execution Environment](docs/execution-environment.md) — what is in the image and how to change it
- [Windows host preparation](docs/windows-host-prep.md) — WinRM, transports, and what to use when
- [Local development](docs/local-dev.md) — the dev harness and how to iterate

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The short version: build logic goes in
the Makefile so all three run paths stay in step, and lint findings get fixed
rather than skipped. Issues labelled `good-first-issue` are scoped to be
approachable.

## Licence

[Apache-2.0](LICENSE).
