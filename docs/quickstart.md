# Quickstart

Getting from a fresh clone to a green connectivity probe. This is the local
path — no AWX, no Kubernetes — because it isolates the two things that
actually go wrong: the image and the WinRM connection.

## What you need

- Python 3.11 or newer, git, and Docker (or Podman via `CONTAINER_RT=podman`)
- A Windows host you can administer. A Windows 11 desktop is fine; so is a
  Windows Server VM.
- Network reachability from where the container runs to that host on port 5985.

You do **not** need AWX, a Kubernetes cluster, or a real SQL Server. The
harness starts a throwaway SQL Server 2022 container for you.

## 1. Set up the toolchain

```bash
git clone https://github.com/ka1ne/ansible-ee.git
cd ansible-ee
make bootstrap
source .venv/bin/activate
make deps
```

`make bootstrap` checks prerequisites and creates `.venv`. `make deps` installs
the Ansible collections, which you need for linting and for running playbooks
outside the container.

## 2. Prepare the Windows host

On the Windows machine, in an Administrator PowerShell:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process -Force
.\dev\scripts\setup-winrm-local.ps1 -WinRMPassword '<a password you generated>'
```

This enables WinRM, restricts authentication to NTLM, opens port 5985 to the
container subnet, and creates a local `ansible` account.

It configures **unencrypted HTTP**, which is acceptable on a trusted local
network and not acceptable anywhere else. For anything beyond a local
experiment, read [windows-host-prep.md](windows-host-prep.md) first.

## 3. Provide credentials

```bash
cp dev/.env.example .env
```

Fill in at least:

| Variable | What it is |
|---|---|
| `WINRM_USER` | The account created in step 2, `ansible` by default |
| `WINRM_PASSWORD` | The password you passed to the script |
| `MSSQL_SA_PASSWORD` | A password for the throwaway SQL Server container |
| `WINRM_HOST` | Only if the target is not the machine running Docker |

`MSSQL_SA_PASSWORD` has to satisfy SQL Server's complexity rules: at least
eight characters with upper case, lower case, a digit and a symbol. The
container will exit silently on startup if it does not.

`.env` is gitignored. Keep it that way.

## 4. Run the probe

```bash
make test-local
```

This builds the Execution Environment, starts SQL Server, waits for it to
accept connections, then runs `playbooks/connectivity_probe.yml` inside the EE
against your Windows host.

A successful run confirms, in order:

1. WinRM works and the credentials are correct
2. Facts can be gathered
3. The Windows host can open a TCP connection to SQL Server
4. A SQL Server login succeeds — skipped if `sqlcmd` is not on the host, which
   is not a failure

## When it does not work

**`.env not found`** — you skipped step 3, or created it in `dev/` instead of
the repository root. It belongs at the root.

**The build cannot reach `galaxy.ansible.com` or the base image registry** —
some corporate networks block both. `make ee-context` still validates the EE
definition and writes a Containerfile without building. Push the branch and let
CI do the build.

**WinRM connection refused or times out** — usually the firewall rule not
matching your container subnet. The script opens 5985 to `172.16.0.0/12`; if
Docker gives your containers addresses outside that range, widen the rule.
Check what the host sees with `Get-NetFirewallRule -DisplayName 'WinRM*'`.

**Authentication fails with a valid password** — NTLM against a local account
needs that account to be a real local user, not a Microsoft account. Confirm
with `Get-LocalUser`.

**SQL Server never becomes ready** — nearly always the SA password failing
complexity rules. Check with `docker logs ansible-ee-mssql`.

For more verbose output, run the playbook directly with `-vvv`:

```bash
ansible-playbook -i inventories/local/hosts.yml playbooks/connectivity_probe.yml -vvv
```

## Next

- [Local development](local-dev.md) — iterating on content without rebuilding
- [Execution Environment](execution-environment.md) — changing what is in the image
- Standing this up in AWX is tracked in
  [#9](https://github.com/ka1ne/ansible-ee/issues/9) and
  [#10](https://github.com/ka1ne/ansible-ee/issues/10)
