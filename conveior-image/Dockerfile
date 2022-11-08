FROM debian:bullseye-slim

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends -o=Dpkg::Use-Pty=0 \
    apt-transport-https \
    ca-certificates \
    cron \
    curl \
    docker.io \
    jq \
    libzip-dev \
    libnginx-mod-http-lua \
    lua5.4 \
    netcat \
    procps \
    vim \
    unzip \
    wget \
    zip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && \
    chmod a+x /usr/local/bin/yq

RUN mkdir -p /var/log /usr/share/nginx/logs && \
    touch /var/log/cron.log

RUN curl -L https://github.com/docker/compose/releases/download/v2.10.2/docker-compose-linux-x86_64 -o '/usr/local/bin/docker-compose' && \
    chmod +x /usr/local/bin/docker-compose && \
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

COPY nginx.conf /etc/nginx/nginx.conf
COPY bin /usr/local/bin
RUN chmod -R +x /usr/local/bin

RUN (crontab -l ; echo "0 19 * * * /usr/local/bin/sys-cron24.sh >> /var/log/cron.log 2>&1") | crontab

WORKDIR /usr/local/bin
EXPOSE 80
USER root
ENTRYPOINT ["/usr/local/bin/sys-entrypoint.sh"]