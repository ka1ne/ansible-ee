# Local development

How to iterate on content without waiting for a container build every time.

## The harness

`make test-local` runs `dev/scripts/run-local.sh`, which:

1. Creates a container network
2. Builds the Execution Environment
3. Starts SQL Server 2022 and waits for it to accept connections
4. Runs the connectivity probe inside the EE against your Windows host
5. Tears everything down on exit, including on failure

Everything it needs comes from `.env` at the repository root.

## Skipping the rebuild

The build is the slow part and you rarely need it. Playbooks and inventories
are bind-mounted into the container at run time, so editing them takes effect
immediately:

```bash
make test-local ARGS=--skip-build      # or:
bash dev/scripts/run-local.sh --skip-build
```

Rebuild when you change `ee/requirements.yml`, `ee/requirements.txt`,
`ee/bindep.txt`, or `ee/execution-environment.yml` — and nothing else.

## Running playbooks directly

Once `make deps` has installed the collections, you can skip the container
entirely for anything that does not depend on being inside the EE:

```bash
source .venv/bin/activate
ansible-playbook -i inventories/local/hosts.yml playbooks/connectivity_probe.yml -vvv
```

This is the fastest loop for developing tasks. Verify inside the EE before
opening a pull request, though — a module that works with your locally
installed collections can still be missing from the image.

## Checks before pushing

```bash
make lint          # yamllint and ansible-lint
make test-syntax   # syntax-check the playbooks
make ee-build      # the full image build
```

`make lint` needs the collections installed, so run `make deps` first. Without
them, ansible-lint cannot resolve module names and reports every Windows task
as an unknown module — a confusing failure that has nothing to do with your
change.

Some findings are in `warn_list` rather than `skip_list` in `.ansible-lint`.
Those are deferred on purpose, each names the issue tracking it, and they are
reported without failing the build. Do not add to that list to get green; fix
the finding or discuss it in the pull request.

## Podman instead of Docker

```bash
export CONTAINER_RT=podman
make ee-build
```

The scripts and the Makefile both honour it. On WSL2 with Podman, the container
subnet may differ from what `setup-winrm-local.ps1` opens the firewall to —
widen the rule if the connection times out.

## Cleaning up

```bash
make clean        # removes the build context and locally built images
make venv-clean   # removes .venv
```

The harness removes its own containers on exit. If a run is killed hard enough
to skip that, remove them by name:

```bash
docker rm -f ansible-ee-mssql ansible-ee-probe
docker network rm ansible-ee-local
```
