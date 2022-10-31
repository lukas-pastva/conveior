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
    nginx \
    procps \
    vim \
    unzip \
    zip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*


RUN mkdir -p /var/log && \
    touch /var/log/cron.log && \
    mkdir /action && \
    chown 33 /action && \
    chmod 777 /action

COPY nginx.conf /etc/nginx/nginx.conf
COPY action /action
RUN chmod -R +x /action

RUN (crontab -l ; echo "*/5 * * * * /action/sys-cron.sh >> /var/log/cron.log 2>&1") | crontab && \
    (crontab -l ; echo "0 19 * * * /action/sys-cron24.sh >> /var/log/cron.log 2>&1") | crontab

WORKDIR /action
EXPOSE 80
ENTRYPOINT ["/action/sys-entrypoint.sh"]