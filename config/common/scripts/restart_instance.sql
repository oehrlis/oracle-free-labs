--------------------------------------------------------------------------------
-- OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
--------------------------------------------------------------------------------
--  Name......: restart_instance.sql
--  Author....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
--  Editor....: Stefan Oehrli
--  Date......: 2026.10.15
--  Revision..: v1.0.0
--  Purpose...: Restart the instance (SHUTDOWN IMMEDIATE, STARTUP) and show the
--              open mode of all PDBs afterwards.
--  Notes.....: - Execute in CDB$ROOT as SYSDBA.
--              - PDBs open again only if their state was saved
--                (ALTER PLUGGABLE DATABASE ... SAVE STATE); the list below
--                shows which did not.
--  License...: Apache License Version 2.0, January 2004 as shown
--              at http://www.apache.org/licenses/
--------------------------------------------------------------------------------
WHENEVER SQLERROR EXIT SQL.SQLCODE
PROMPT - Restart instance to apply SPFILE changes
SHUTDOWN IMMEDIATE;
STARTUP;
PROMPT - PDB open modes after restart
COL name FOR A30
SELECT name, open_mode FROM v$pdbs ORDER BY con_id;
-- EOF -------------------------------------------------------------------------
