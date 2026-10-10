# conveior - backup/restore CLI + the step image of the Argo "events" chart (replaced the old bashie image 2026-10-10).
FROM debian:bookworm-slim

ARG KUBECTL_VERSION=v1.33.6
ARG YQ_VERSION=v4.54.1
ARG RCLONE_VERSION=v1.75.2
ARG HELM_VERSION=v3.22.0
ARG HELM_SHA256=1e4ab49e429626cf6c6958d914248b78c9730803c2751b87627e171dc800e7bb
ARG ARGOCD_VERSION=v3.1.0
ARG ARGOCD_SHA256=e66a334908fdc74fe128a498c864f04159a9c04b49534a94e032173f0df019ee
# terraform stays on the version the tfstate was written with (bashie had 1.7.4)
ARG TERRAFORM_VERSION=1.7.4
ARG TERRAFORM_SHA256=285539a6fd62fb79f05edc15cc207ca90f282901c32261085ea0642a0d638dfd

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
      bash ca-certificates curl git jq mariadb-client openssh-client procps unzip zip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# kubectl, yq, rclone (backup CLI)
RUN curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    echo "$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256")  /usr/local/bin/kubectl" | sha256sum -c - && \
    chmod +x /usr/local/bin/kubectl && \
    curl -fsSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" && \
    chmod +x /usr/local/bin/yq && \
    curl -fsSL -o /tmp/rclone.zip "https://downloads.rclone.org/${RCLONE_VERSION}/rclone-${RCLONE_VERSION}-linux-amd64.zip" && \
    unzip -q -j /tmp/rclone.zip '*/rclone' -d /usr/local/bin && chmod +x /usr/local/bin/rclone && rm -f /tmp/rclone.zip && \
    kubectl version --client >/dev/null && yq --version && rclone version | head -n 1

# helm, argocd, terraform (events chart steps: deploy, stop, install, terraform), all checksum verified
RUN curl -fsSL -o /tmp/helm.tgz "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" && \
    echo "${HELM_SHA256}  /tmp/helm.tgz" | sha256sum -c - && \
    tar -xzf /tmp/helm.tgz --strip-components=1 -C /usr/local/bin linux-amd64/helm && rm -f /tmp/helm.tgz && \
    curl -fsSL -o /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64" && \
    echo "${ARGOCD_SHA256}  /usr/local/bin/argocd" | sha256sum -c - && chmod +x /usr/local/bin/argocd && \
    curl -fsSL -o /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" && \
    echo "${TERRAFORM_SHA256}  /tmp/terraform.zip" | sha256sum -c - && \
    unzip -q /tmp/terraform.zip terraform -d /usr/local/bin && chmod +x /usr/local/bin/terraform && rm -f /tmp/terraform.zip && \
    helm version --short && argocd version --client --short && terraform version

COPY lib/ /usr/local/lib/conveior/
COPY bin/ /usr/local/bin/
RUN chmod +x /usr/local/bin/conveior /usr/local/bin/entrypoint.sh /usr/local/bin/backup.sh

# bash helper libraries of the events chart (gitlab_backup, vault_*, k8s_*); scripts do `source functions.inc.sh`
# from the working directory, so they live in /tmp/app exactly like in the old bashie image
COPY toolbox/ /tmp/app/
WORKDIR /tmp/app

ENV CONVEIOR_LIB=/usr/local/lib/conveior \
    CONFIG_FILE_DIR=/home/config.yaml

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
