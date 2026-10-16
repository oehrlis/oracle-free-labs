#!/bin/bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Name.......: 20_seclab_apply_secpdb1.sh
# Author.....: Stefan Oehrli (oes), stefan.oehrli@oradba.ch
# Editor.....: Stefan Oehrli
# Date.......: 2026.10.15
# Revision...: v1.0.0
# Purpose....: seclab - apply the insecure baseline S01-S11 to SECPDB1 and
#              verify it. Same entry point as scripts/apply_usecase.sh.
# Notes......: *** INTENTIONALLY INSECURE - lab use only ***
#              runUserScripts.sh of the Oracle image sources *.sh files
#              (". file"). The body runs in a subshell, so set -euo pipefail
#              and exit stay local and cannot end the script runner.
# Reference..: doc/seclab.md
# License....: Apache License Version 2.0, January 2004 as shown
#              at http://www.apache.org/licenses/
# ------------------------------------------------------------------------------
(
    set -euo pipefail
    /opt/oracle/common/scripts/seclab_apply.sh -p SECPDB1
) || echo "ERROR: 20_seclab_apply_secpdb1.sh failed - see output above" >&2
# - EOF ------------------------------------------------------------------------
