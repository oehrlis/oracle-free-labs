#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 01_setup_network_wallet.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.15
# Revision...: v1.0.0
# Purpose....: Run common network/wallet persistence setup for the seclab service
# Notes......: runUserScripts.sh of the Oracle image sources *.sh files
#              (". file"). The body runs in a subshell, so set -euo pipefail
#              and exit stay local and cannot end the script runner.
# Reference..: doc/seclab.md
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
(
    set -euo pipefail
    /opt/oracle/common/scripts/setup_network_wallet.sh
) || echo "ERROR: 01_setup_network_wallet.sh failed - see output above" >&2
# - EOF ------------------------------------------------------------------------
