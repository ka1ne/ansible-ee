# Preparing Windows hosts

Ansible reaches Windows over WinRM. Most problems people hit with Windows
automation are connection problems, and most connection problems come from
picking the wrong transport for the situation.

## Choosing a transport

| Situation | Transport | Port | Notes |
|---|---|---|---|
| Local machine, workgroup, trusted network | NTLM over HTTP | 5985 | What `setup-winrm-local.ps1` configures. Development only — traffic is unencrypted. |
| Standalone or workgroup server | NTLM over HTTPS | 5986 | Needs a certificate on the listener. |
| Domain-joined, no second hop | Kerberos over HTTPS | 5986 | The right default in a domain. Uncomment the Kerberos packages in `ee/requirements.txt`. |
| Domain-joined, needs a second hop | CredSSP over HTTPS | 5986 | Required when the playbook reaches a file share or another server *from* the Windows host. Delegates credentials, so enable it deliberately. |

The second hop is the one that catches people out. NTLM and Kerberos without
delegation cannot authenticate onward from the Windows host, so a task that
copies from a UNC path fails with access denied even though the connection to
the host itself works.

`inventories/example/group_vars/windows.yml` defaults to CredSSP over HTTPS
because that is the common case for the IIS and SQL Server content here.
`inventories/local/hosts.yml` uses NTLM over HTTP because it targets your own
machine.

## Local development setup

```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process -Force
.\dev\scripts\setup-winrm-local.ps1 -WinRMPassword '<a password you generated>'
```

This enables WinRM, restricts authentication to Negotiate (covering NTLM),
allows unencrypted traffic, opens port 5985 to `172.16.0.0/12`, and creates a
local `ansible` account.

Two things about it are only acceptable locally: unencrypted HTTP, and a local
account with a password you typed. Do not run it against anything that matters.

## Production setup

Broadly, on each target:

1. Enable WinRM: `Enable-PSRemoting -Force`.
2. Create an HTTPS listener on 5986 with a certificate your automation host
   trusts. Certificates from your internal CA are the sane choice; self-signed
   works but means `ansible_winrm_server_cert_validation: ignore`, which throws
   away most of the benefit.
3. Disable the HTTP listener: `Remove-Item WSMan:\localhost\Listener\* -Recurse`
   for the HTTP one specifically.
4. Turn off `AllowUnencrypted`.
5. Restrict the firewall rule for 5986 to your automation hosts, not `Any`.
6. Use a dedicated service account with only the privileges the playbooks need,
   rather than a domain administrator.

Once hosts present certificates you trust, set
`ansible_winrm_server_cert_validation: validate` in the group vars. It is
`ignore` in the example inventory only so a lab works out of the box.

## Credentials

Nothing in this repository stores credentials. Playbooks and inventories read
them from the environment:

| Variable | Used for |
|---|---|
| `WINRM_HOST` | Target address, when it is not the container host |
| `WINRM_USER` | WinRM account |
| `WINRM_PASSWORD` | WinRM password |
| `MSSQL_HOST` | SQL Server address *as the Windows host sees it* |
| `MSSQL_SA_PASSWORD` | SQL Server SA password |

The same names are used in three places, on purpose: `.env` locally, the
`winrm-credentials` Kubernetes secret for Tekton, and the AWX credential types
being added in [#11](https://github.com/ka1ne/ansible-ee/issues/11). One set of
names means the playbooks do not care which one is driving them.

For Tekton, create the secret with those keys — `envFrom` maps them straight to
environment variables:

```bash
kubectl create secret generic winrm-credentials \
  --from-literal=WINRM_HOST=<address> \
  --from-literal=WINRM_USER=<account> \
  --from-literal=WINRM_PASSWORD=<password> \
  --from-literal=MSSQL_HOST=<address> \
  --from-literal=MSSQL_SA_PASSWORD=<password> \
  -n <namespace>
```

## Checking it works

The connectivity probe exists for exactly this and is the fastest way to tell a
credential problem from a network problem:

```bash
make test-local
```

Or against an arbitrary inventory:

```bash
ansible-playbook -i <inventory> playbooks/connectivity_probe.yml -vvv
```

A bare `win_ping` narrows it further:

```bash
ansible -i <inventory> windows -m ansible.windows.win_ping -vvv
```
