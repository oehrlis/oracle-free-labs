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

ARG DB_IMAGE=container-registry.oracle.com/database/free:latest-lite

FROM ${DB_IMAGE}

LABEL org.opencontainers.image.title="oracle-free-labs" \
      org.opencontainers.image.description="Extended Oracle AI Database Free for OraDBA labs" \
      org.opencontainers.image.authors="Stefan Oehrli <stefan.oehrli@oradba.ch>" \
      org.opencontainers.image.source="https://github.com/oehrlis/oracle-free-labs" \
      org.opencontainers.image.licenses="Apache-2.0"

USER root

# Install additional tools: rlwrap (for sqlplus history), less, oradba init
RUN microdnf install -y rlwrap less tar gzip && \
    microdnf clean all && \
    rm -rf /var/cache/yum /tmp/*.rpm

USER oracle
# - EOF ------------------------------------------------------------------------
