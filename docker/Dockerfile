# XAO::Web base container image.
#
# In most cases it needs to be extended for specific projects to pull in
# additional software dependencies, set the environment, logging, etc.
#
# Default site demo:
#   docker run -p 8080:80 amaltsev/xao-web
#
# Mount and execute a site from the current directory:
#   docker run -p 8080:80 -v $(pwd):/opt/xao/projects/app amaltsev/xao-web
#------------------------------------------------------------------------------

# Software versions to pull. Use --build-arg to override:
#  docker build --build-arg XAO_WEB_VERSION=1.66 -t xao-web:1.66 .
#
ARG CENTOS_VERSION=centos7
ARG XAO_BASE_VERSION=master
ARG XAO_FS_VERSION=master
ARG XAO_WEB_VERSION=master

# CentOS makes for an easier to use environment.
#
FROM centos:$CENTOS_VERSION

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
        2>&1 \
    && \
    cpanm \
        Plack \
        Plack::Middleware::Debug \
        Starman \
        https://api.github.com/repos/amaltsev/perl-Test-Unit/tarball/0.29 \
        https://api.github.com/repos/amaltsev/XAO-Base/tarball/$XAO_BASE_VERSION \
        https://api.github.com/repos/amaltsev/XAO-FS/tarball/$XAO_FS_VERSION \
        https://api.github.com/repos/amaltsev/XAO-Web/tarball/$XAO_WEB_VERSION \
        2>&1 \
    && \
    rm -rf /root/.cpanm /usr/local/share/man

# Exposing 80, re-route as needed with:
#   docker run --publish 8080:80 amaltsev/xao-web:latest
#
EXPOSE 80

# The default site name, override with:
#   docker run --env XAO_SITE_NAME=yoursite ...
#
# Optionally also mount your site code into container:
#   docker run -v $(pwd):/opt/xao/projects/app
#
ENV XAO_SITE_NAME="app"

# Run with plackup by default, for starman use:
#  docker run --env PSGI_RUNNER=starman ...
#
ENV PSGI_RUNNER="plackup"

# Specify additional Starman/Plackup options on docker
# run command line if needed.
#
CMD if [ -f /opt/xao/projects/$XAO_SITE_NAME/cpanfile ]; then \
        cd /opt/xao/projects/$XAO_SITE_NAME; \
        cpanm . --installdeps; \
    fi; \
    $PSGI_RUNNER \
        --port 80 \
        --user nobody \
        --group nobody \
        -R "/opt/xao/projects/$XAO_SITE_NAME/objects,/opt/xao/projects/$XAO_SITE_NAME/templates" \
        /opt/xao/handlers/xao.psgi
