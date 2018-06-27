FROM centos:centos7 AS xao-web

# Software versions to pull
#
ARG XAO_BASE_VERSION=1.17
ARG XAO_FS_VERSION=1.18
ARG XAO_WEB_VERSION=1.65

# MariaDB repository
#
COPY MariaDB.repo /etc/yum.repos.d/MariaDB.repo
RUN rpm --import https://yum.mariadb.org/RPM-GPG-KEY-MariaDB

# Basic package dependencies
#
RUN yum upgrade -y              \
    && \
    yum install -y              \
        gcc                     \
        perl-App-cpanminus      \
        perl-LWP-Protocol-https \
        openssl-devel           \
        MariaDB-devel           \
    && \
    rm -rf /var/cache/yum

# File::ShareDir fails normal installation
#
RUN cpanm \
        --force File::ShareDir \
    && \
    cpanm \
        Plack \
        Plack::Middleware::Debug \
        Starman \
        https://api.github.com/repos/amaltsev/perl-Test-Unit/tarball/0.29 \
        https://api.github.com/repos/amaltsev/XAO-Base/tarball/$XAO_BASE_VERSION \
        https://api.github.com/repos/amaltsev/XAO-FS/tarball/$XAO_FS_VERSION \
        https://api.github.com/repos/amaltsev/XAO-Web/tarball/$XAO_WEB_VERSION \
    && \
    rm -rf /root/.cpanm /usr/local/share/man

# Exposing 80, re-route as needed with:
#   docker run --publish 8080:80
#
EXPOSE 80

# The default site name, override with:
#   docker run --env XAO_SITE_NAME=yoursite
#
ENV XAO_SITE_NAME="app"

# Specify additional Starman options on docker
# run command line if needed.
#
ENTRYPOINT [ \
    "starman", \
        "--port","80", \
        "--user","nobody", \
        "--group","nobody", \
        "/opt/xao/handlers/xao.psgi" \
    ]
