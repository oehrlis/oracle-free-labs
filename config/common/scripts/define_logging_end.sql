-- -----------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
-- -----------------------------------------------------------------------------
--  Name......: define_logging_end.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2025.08.20
--  Revision..: v1.0.0
--  Purpose...: End logging for script execution (SPOOL OFF).
--  Notes.....: To be included at the end of scripts paired with
--              define_logging_begin.sql.
--  Reference.: --
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
-- -----------------------------------------------------------------------------

PROMPT - Log file: &LOG_DIR./&LOG_PREFIX._&db_name._&pdb_name._&log_date..log
PROMPT - Logging finished
SPOOL OFF
-- EOF -------------------------------------------------------------------------
