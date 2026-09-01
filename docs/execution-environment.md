# The Execution Environment

An Execution Environment is the container image Ansible runs inside. It bundles
ansible-core, the collections, and the Python libraries the modules need, so a
playbook behaves the same on your laptop, in AWX, and in a pipeline.

This project's image is defined entirely by `ee/execution-environment.yml` and
published as `ghcr.io/ka1ne/ansible-ee`.

## One definition, three build paths

| Where | How |
|---|---|
| Locally | `make ee-build` |
| GitHub Actions | `make ee-build`, then `make ee-push` on `main` |
| Tekton | `make ee-context`, then buildah over the generated context |

All three read the same file. This is the point: a build recipe copied into a
pipeline is a build recipe that will drift, and the drift only surfaces when
something fails in one place and not another.

`make ee-context` is worth knowing about on its own — it runs `ansible-builder
create` to generate the `Containerfile` and build context without building
anything, which validates the definition and is fast.

## What is in the image

**Base:** `registry.access.redhat.com/ubi9:latest`. UBI9 pulls without a Red
Hat login and ships Python 3 and dnf. Override it with `EE_BASE_IMAGE`; if you
move to a minimal base, also change `package_manager_path` to
`/usr/bin/microdnf`.

**Collections** (`ee/requirements.yml`):

| Collection | Why |
|---|---|
| `ansible.windows` | `win_ping`, `win_feature`, `setup`, `win_shell` |
| `community.windows` | The IIS modules the roles currently use |
| `microsoft.iis` | Where the IIS modules are moving ([#13](https://github.com/ka1ne/ansible-ee/issues/13)) |
| `lowlydba.sqlserver` | dbatools-backed SQL Server management |
| `awx.awx` | Talking to AWX |
| `infra.controller_configuration` | Applying this project's AWX config-as-code |

**Python** (`ee/requirements.txt`): `pywinrm` with the NTLM and CredSSP
transports, plus `jmespath` and `xmltodict` for filters the playbooks use.
Kerberos support is present in `bindep.txt` at the system level but the Python
packages are commented out — uncomment them when you have a domain-joined
target, since they add build time for everyone who does not.

**System** (`ee/bindep.txt`): a compiler toolchain for the native extensions,
the krb5 client libraries, and DNS tools.

## Version pinning

`ansible.windows` and `community.windows` are pinned exactly, because the
existing roles depend on their module behaviour. The rest carry lower bounds
until the first green CI build reports what actually resolves, at which point
they should be pinned too — tracked in
[#2](https://github.com/ka1ne/ansible-ee/issues/2).

`ansible-core` is bounded rather than pinned (`>=2.17,<2.21`) so security
updates land without a code change, while a major version cannot arrive by
surprise.

The floor is 2.17 for a reason worth knowing about. UBI9's default `python3`
is 3.9, and ansible-core past 2.15 needs Python 3.10 or newer on the
controller. Left to itself, pip quietly resolves to ansible-core 2.15 — which
is end-of-life — and the build still succeeds. The definition therefore pins
the interpreter to `python3.11` via `python_interpreter`, and CI prints
`ansible --version` on every run so a regression like that cannot pass
unnoticed again.

## Changing the image

Add a collection to `ee/requirements.yml` or a Python package to
`ee/requirements.txt`, then:

```bash
make ee-build
make ee-shell     # poke around inside the result
```

Inside the image, `ansible-galaxy collection list` and `pip list` tell you what
you actually got, which is not always what you asked for once dependency
resolution has had its say.

CI runs those same checks on every pull request, so a collection that fails to
resolve fails the build rather than surfacing later as a missing module.

## Behind a proxy or an internal mirror

The definition supports an internal Galaxy mirror through two build arguments:

```bash
ansible-builder build --file ee/execution-environment.yml \
  --build-arg GALAXY_MIRROR_URL=https://hub.internal/api/galaxy/ \
  --build-arg GALAXY_MIRROR_TOKEN=... \
  --tag ghcr.io/ka1ne/ansible-ee:local
```

When `GALAXY_MIRROR_URL` is empty the step does nothing and the build uses
public Galaxy, so the same definition works in both places. The final image
always gets the repository's `ansible.cfg`, written after the mirror
configuration so no build-time credentials survive into the published image.

## Where the ansible.cfg comes from

The repository root `ansible.cfg` is copied into the build context via
`additional_build_files` and installed to `/etc/ansible/ansible.cfg` in the
final image. There is deliberately no default inventory in it — every run path
passes `-i` explicitly, and a default would make running against the wrong
hosts too easy.
