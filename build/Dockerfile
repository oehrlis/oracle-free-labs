# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: Dockerfile
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.04.15
# Version....: v1.0.0
# Purpose....: Extended Oracle AI Database Free image with oradba tools,
#              rlwrap, and less pre-installed for lab use.
# Notes......: Build: make build
#              Usage: set DB_IMAGE=oracle-free-labs:latest in .env
# Reference..: https://github.com/oehrlis/oracle-free-labs
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------

ARG DB_IMAGE=container-registry.oracle.com/database/free:23.9.0.0
FROM ${DB_IMAGE}

USER root

# Fix OCI region mirror resolution: $ociregion/$ocidomain do not resolve in
# container builds outside OCI. Affects all *.repo files (oracle-linux-ol8.repo,
# oraclelinux-developer-ol8.repo, uek-ol8.repo, virt-ol8.repo).
# sed must run twice: once before oracle-epel-release-el8 (fixes existing repos),
# once after (fixes the EPEL repo file dropped by the package install).
# Double sed is required for multi-arch (amd64 + arm64) — no arch-specific URLs.
RUN sed -i \
        's|baseurl=https://yum\$ociregion\.\$ocidomain/|baseurl=https://yum.oracle.com/|g' \
        /etc/yum.repos.d/*.repo && \
    dnf install -y oracle-epel-release-el8 && \
    sed -i \
        's|baseurl=https://yum\$ociregion\.\$ocidomain/|baseurl=https://yum.oracle.com/|g' \
        /etc/yum.repos.d/*.repo && \
    dnf install -y rlwrap less curl && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# Create /opt/oracle/local as root before switching to oracle user
# (oradba_install.sh requires the parent directory to exist)
RUN mkdir -p /opt/oracle/local && chown oracle:oinstall /opt/oracle/local

# Create /opt/oracle/network/admin symlink for named services.
# Resolves at runtime when the dbconfig bind mount is attached; dangling
# until then, which is harmless. cdbfree uses Oracle's own $ORACLE_HOME/network/admin.
RUN mkdir -p /opt/oracle/network && \
    ln -sf /opt/oracle/dbconfig/FREE /opt/oracle/network/admin && \
    chown -h oracle:oinstall /opt/oracle/network

# Install oradba tools as oracle user with profile update
# Pass --build-arg ORADBA_CACHEBUST=$(date +%s) to force a fresh download
# without invalidating the dnf layers above.
ARG ORADBA_CACHEBUST=0
USER oracle
RUN curl -fsSL \
        https://github.com/oehrlis/oradba/releases/latest/download/oradba_install.sh \
        -o /tmp/oradba_install.sh && \
    chmod +x /tmp/oradba_install.sh && \
    /tmp/oradba_install.sh --update-profile && \
    rm -f /tmp/oradba_install.sh

# EOF -------------------------------------------------------------------------