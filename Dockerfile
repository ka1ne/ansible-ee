FROM registry.access.redhat.com/ubi9/python-311:latest
# POC alternative if internal UBI isn't available: python:3.11-slim

USER root

# ── POC: WinRM only (NTLM/CredSSP transport) ─────────────────────────────────
# Fast-follower: uncomment the krb5-* lines below when adding Kerberos support
RUN microdnf install -y \
        gcc \
        python3-devel \
        openssl-devel \
        # krb5-devel \
        # krb5-libs \
        # krb5-workstation \
    && microdnf clean all

# Python deps — pinned for reproducibility
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# ansible-core — pinned minor, patch auto-resolved at build time
RUN pip install --no-cache-dir "ansible-core==2.17.*"

# Ansible collections
COPY requirements.yml /tmp/requirements.yml
RUN ansible-galaxy collection install -r /tmp/requirements.yml

# Ansible config
COPY ansible.cfg /etc/ansible/ansible.cfg

# Copy playbooks + roles + inventory into the image
# (in pipeline use: mount repo via git clone step or shared volume instead)
COPY playbooks/ /runner/playbooks/
COPY roles/     /runner/roles/
COPY inventory/ /runner/inventory/
COPY scripts/   /runner/scripts/

USER 1000
WORKDIR /runner
