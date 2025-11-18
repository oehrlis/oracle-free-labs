rem ---------------------------------------------------------------------------
rem  Trivadis AG, Baden-Daettwil/Basel/Bern/Lausanne/Zuerich
rem               Duesseldorf/Frankfurt/Freiburg i.Br./Hamburg/Muenchen/Stuttgart
rem               Wien
rem               Switzerland/Germany/Austria Internet: http://www.trivadis.com
rem ---------------------------------------------------------------------------
rem $Id: 50fc9944a869ad846f43678edff1c4c39e8476a5 $
rem ---------------------------------------------------------------------------
rem  Group/Privileges.: DBA
rem  Script Name......: sdts.sql
rem  Developer........: Urs Meier
rem  Date.............: 14.11.1994
rem  Version..........: Oracle Database 11g
rem  Description......: Display free space in all tablespaces as well as
rem                     free-space fragmentation
rem  Usage............: 
rem  Input parameters.: 
rem  Output...........: 
rem  Called by........:
rem  Requirements.....: 
rem  Remarks..........: 
rem
rem ---------------------------------------------------------------------------
rem Changes:
rem DD.MM.YYYY Developer Change
rem ---------------------------------------------------------------------------
rem 02.08.1997 AnK       Oracle8 (added contents to status and 
rem                      prompt comments at the end)
rem 21.04.1999 AnK       Added locally managed tablespaces. 
rem 21.04.1999 AnK       Show also full tablespaces
rem 27.11.2001 SvV       Show SUM_FREE und %FREE in tempfile temp-ts
rem 30.11.2001 SvV       Show correct values for full locally managed-ts
rem 05.04.2002 MaW       Added display of autoextend
rem 08.27.2002 MaW       OK for Oracle9i R2
rem 06.10.2002 FaR       Changed NULL to 0 in union
rem 29.11.2004 MaW       Added Segement Space Management
rem 18.10.2007 ChA       Fixed formatting problem because of cursor_sharing
rem                      and show MB instead of bytes
rem 24.10.2007 ChA       Fixed footer
rem 07.01.2008 ChA       Removed hint RULE + tuning
rem 19.11.2008 ChA       Fixed header + OK for 11g + added info about encryption
rem 13.01.2015 FCE	 Adapted for 12c; added CON_ID and CON_NAME
rem 27.11.2015 APi       Fixed CON_ID in cdb_free_space query
rem 17.04.2018 ZaM       Show con_id, con_name only in CDBs
rem ---------------------------------------------------------------------------

set logsource "Dummy"
store set temp.tmp replace
clear   columns -
        breaks -
        computes
set pagesize 100 linesize 145

col show_id noprint new_value show_id
col show_name noprint new_value show_name

set termout off
select decode(sys_context('userenv','con_id'),0,'noprint','format a15') show_name,
       decode(sys_context('userenv','con_id'),0,'noprint','format 999') show_id
from dual;
set termout on

@@foenvtit "Tablespace statistics"

column tablespace_name format a30
column status format a3 trunc
column extent_management format a3 trunc heading MGM
column allocation_type format a3 trunc heading ALL
column space_management format a1
column auto format a1
column logging format a1 heading L
column encrypted format a1 heading E
column t format 9,999,990 heading TOTAL_MB
column s format 9,999,990 heading SUM_FREE_MB
column m format 9,999,990 heading MAX_FREE_MB
column c format 9,990 heading COUNT
column p format 990.0 heading "% FREE"
rem column con_name format a30
rem column con_id format 999
column con_name &&show_name
column con_id &&show_id

SELECT dt.con_id,con.name con_name, dt.tablespace_name,substr(dt.status,1,2)||substr(contents,1,1) STATUS,
       dt.extent_management, 
        decode(dt.extent_management,'LOCAL',decode(dt.allocation_type,'USER','MIG',dt.allocation_type),dt.allocation_type) allocation_type,
       substr(segment_space_management,1,1) space_management,
       decode(t.auto,0,'N','Y') auto,
       decode(dt.logging,'LOGGING','Y','N') logging,
       substr(dt.encrypted,1,1) encrypted,
       round(t.t/1024/1024) t, round(nvl(u.s,0)/1024/1024) s, nvl(u.s/t.t*100,0) p, round(nvl(u.m,0)/1024/1024) m, nvl(u.c,0) c
  FROM cdb_tablespaces dt,v$containers con, 
       (SELECT con_id, tablespace_name,SUM(bytes) s, MAX(bytes) m, COUNT(*) c
          FROM cdb_free_space
         GROUP BY con_id, tablespace_name) u,
       (SELECT con_id, tablespace_name,SUM(bytes) t, sum(decode(autoextensible,'YES',1,0)) auto
          FROM cdb_data_files
         GROUP BY con_id, tablespace_name) t
 WHERE dt.tablespace_name = u.tablespace_name(+) and dt.con_id = u.con_id(+)
   AND dt.tablespace_name = t.tablespace_name    and dt.con_id = t.con_id
   and dt.con_id=con.con_id
 UNION
SELECT dt.con_id, con.name con_name, dt.tablespace_name,substr(dt.status,1,2)||substr(contents,1,1) STATUS,
       dt.extent_management, 
        decode(dt.extent_management,'LOCAL',decode(dt.allocation_type,'USER','MIG',dt.allocation_type),dt.allocation_type) allocation_type,
       substr(segment_space_management,1,1) space_management,
       decode(t.auto,0,'N','Y') auto,
       decode(dt.logging,'LOGGING','Y','N') logging,
       substr(dt.encrypted,1,1) encrypted,
       round(t.t/1024/1024) t, round((t.t-nvl(u.s,0))/1024/1024) s, ((t.t-nvl(u.s,0))/t.t*100) p, 0 m, 0 c
  FROM cdb_tablespaces dt, v$containers con, 
       (SELECT con_id, tablespace_name,SUM(bytes_cached) s
          FROM v$temp_extent_pool 
         GROUP BY con_id, tablespace_name) u,
       (SELECT con_id, tablespace_name,SUM(bytes) t, sum(decode(autoextensible,'YES',1,0)) auto
          FROM cdb_temp_files
         GROUP BY con_id, tablespace_name) t
 WHERE dt.tablespace_name = u.tablespace_name(+) and dt.con_id = u.con_id(+)
   AND dt.tablespace_name = t.tablespace_name    and dt.con_id = t.con_id
     and dt.con_id=con.con_id
 ORDER BY 1,3;
 
column tablespace_name clear
column status clear
column con_name clear
column t clear
column s clear
column m clear
column c clear
column p clear
ttitle off
prompt
prompt STA: ON=Online OF=Offline P=Permanent T=Temporary U=Undo R=Read only
prompt MGM: LOC=Locally managed DIC=Dictionary managed
prompt ALL: SYS=Autoallocate UNI=Uniform USE=Dictionary managed MIG=Uniform migrated with DBMS_SPACE_ADMIN
prompt S  : Segment space management is (A)uto or (M)anual
prompt A  : Y=Tablespace contains autoextensible files N=Tablespace contains no autoextensible files
prompt L  : Y=LOGGING N=NOLOGGING
prompt E  : Y=Encrypted N=Not encrypted
prompt
@temp.tmp
