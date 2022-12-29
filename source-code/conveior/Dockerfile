FROM debian:bullseye-slim

WORKDIR /usr/local/bin

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
    zip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN curl https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o yq

RUN mkdir -p /var/log /usr/share/nginx/logs && touch /var/log/cron.log
RUN (crontab -l ; echo "0 19 * * * /usr/local/bin/backup.sh >> /var/log/cron.log 2>&1") | crontab

COPY ./source-code/conveior/nginx.conf /etc/nginx/nginx.conf
COPY ./source-code/conveior/bin /usr/local/bin
RUN chmod -R +x /usr/local/bin

EXPOSE 80
USER root
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]