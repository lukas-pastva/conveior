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
    netcat \
    procps \
    vim \
    unzip \
    zip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*


RUN mkdir -p /var/log /usr/share/nginx/logs && \
    touch /var/log/cron.log && \
    mkdir /bin && \
    chown 33 /bin && \
    chmod 777 /bin

COPY nginx.conf /etc/nginx/nginx.conf
COPY bin /usr/local/bin
RUN chmod -R +x /usr/local/bin

RUN (crontab -l ; echo "0 19 * * * /usr/local/bin/sys-cron24.sh >> /var/log/cron.log 2>&1") | crontab

#(crontab -l ; echo "*/5 * * * * /usr/local/bin/sys-cron.sh >> /var/log/cron.log 2>&1") | crontab && \

WORKDIR /usr/local/bin
EXPOSE 80
USER root
ENTRYPOINT ["/usr/local/bin/sys-entrypoint.sh"]