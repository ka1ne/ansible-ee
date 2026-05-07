FROM registry.access.redhat.com/ubi9/python-311:latest

USER root

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt && \
    pip install --no-cache-dir "ansible-core==2.17.*"

COPY requirements.yml /tmp/requirements.yml
RUN ansible-galaxy collection install -r /tmp/requirements.yml

COPY ansible.cfg /etc/ansible/ansible.cfg

USER 1001
WORKDIR /runner
