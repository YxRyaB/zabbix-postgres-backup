#!/bin/bash
###### OPTIONS #########
# Backup rotation counter
MAX_COPIES_COUNTER=2
# Backup dir
BKUPDIR=/home/backup/archive
# Prefix name
APPNAMEDB=zabbix-db
APPNAMEFILE=zabbix-config
# User name and password for zabbix db
CONNECTION="-U postgres"
# Paths for backup files
FILEDB="/home/backup/archive/zabbix-db-$(date +%Y%m%d).sql"
FILECONFIG="/home/backup/archive/zabbix-config-$(date +%Y%m%d).tar"
# Default dump options
OPTIONS="-d zabbix"
#######################
function alert(){
#usage: alert $APP $MSG $EXIT_CODE(optional) $TO(optional)
APP=$1 #name of application that failed
MSG="$2" #short reason of failure, for example "scp failure" or "failed to move backups" (optional)
EXIT_CODE="$3" #exit code, passed from script(optional)
if [ -z $4 ]
then
  TO="example@email.ru" #default value
else
  TO=$4 #comma separated list of emails
fi
[ -z $EXIT_CODE ] && EXIT_CODE="Undefined"
/usr/sbin/sendmail "$TO" <<EOF
subject:Failed backup of $APP on zabbix-server
from:zabbix@example.ru
to:$TO
Dear,
Backup of application $APP has failed.
Reason is: $MSG
Exit code is: $EXIT_CODE

Please, fix this ASAP.
Sincerely yours,
zabbix-server
EOF
}

function log()
{
  echo "$(date) | $*"
}

function checkFailure
{
  EC=$?
  if [[ $EC != 0 ]]
  then
    log "Step failed with exit code $EC"
    alert zabbix "backup failed" $EC
    exit 1
  fi
}

function rotation-db
{
log "rm old db archive"
COPIES_COUNTERdb=$(ls "$BKUPDIR" | grep "$APPNAMEDB" | wc -l)
if [ "$COPIES_COUNTERdb" -gt "$MAX_COPIES_COUNTER" ]
then
NEED_TO_DELETE_COUNTERdb=$(($(ls "$BKUPDIR" | grep "$APPNAMEDB" | wc -l)-$MAX_COPIES_COUNTER))
for (( i==1; i<$NEED_TO_DELETE_COUNTERdb; i++ ))
do
log "$BKUPDIR/$(ls $BKUPDIR | grep "$APPNAMEDB" | sort | head -n 1)"
rm $BKUPDIR/$(ls $BKUPDIR | grep "$APPNAMEDB" | sort | head -n 1)
done
fi
checkFailure
}

function rotation-file
{
log "rm old file archive"
COPIES_COUNTERfile=$(ls "$BKUPDIR" | grep "$APPNAMEFILE" | wc -l)
if [ "$COPIES_COUNTERfile" -gt "$MAX_COPIES_COUNTER" ]
then
NEED_TO_DELETE_COUNTERfile=$(($(ls "$BKUPDIR" | grep "$APPNAMEFILE" | wc -l)-$MAX_COPIES_COUNTER))
for (( j==1; j<$NEED_TO_DELETE_COUNTERfile; j++ ))
do
log "$BKUPDIR/$(ls $BKUPDIR | grep "$APPNAMEFILE" | sort | head -n 1)"
rm $BKUPDIR/$(ls $BKUPDIR | grep "$APPNAMEFILE" | sort | head -n 1)
done
fi
checkFailure
}

function archive
{
# Copy zabbix files
log "Start compress data and db"
gzip -9 "${FILEDB}"
if [ $? -ne 0 ]
then
 rm "$BKUPDIR"/zabbix-db-`date +%Y%m%d`.sql.gz
 alert zabbix "sql backup compress failed"
fi
tar -rf "${FILECONFIG}" /etc/httpd/conf.d/zabbix.conf 2>&1
tar -rf "${FILECONFIG}" /etc/zabbix 2>&1
tar -rf "${FILECONFIG}" /usr/lib/zabbix 2>&1
tar -rf "${FILECONFIG}" /usr/share/zabbix 2>&1
tar -rf "${FILECONFIG}" /etc/php-fpm.d 2>&1
tar -rf "${FILECONFIG}" /etc/nginx/conf.d/zabbix.12.conf 2>&1
tar -rf "${FILECONFIG}" /etc/php.ini 2>&1
gzip -9 "${FILECONFIG}"
if [ $? -ne 0 ]
then
 rm "$BKUPDIR"/zabbix-config-`date +%Y%m%d`.tar.gz
 alert zabbix "config backup compress failed"
fi
log "Finish compress data and db"
}

function owner
{
log "changed own rule"
chown -R backup:backup $BKUPDIR
if [ $? -ne 0 ]
then
 alert zabbix "don't changed own rule on $BKUPDIR"
fi
}

function pgdamp
{
log "Start backup db"
pg_dump $CONNECTION $OPTIONS -f $FILEDB \
--exclude-table-data=zabbix.acknowledges \
--exclude-table-data=zabbix.alerts \
--exclude-table-data=zabbix.auditlog \
--exclude-table-data=zabbix.auditlog_details \
--exclude-table-data=zabbix.escalations \
--exclude-table-data=zabbix.events \
--exclude-table-data=zabbix.history \
--exclude-table-data=zabbix.history_log \
--exclude-table-data=zabbix.history_str \
--exclude-table-data=zabbix.history_str_sync \
--exclude-table-data=zabbix.history_sync \
--exclude-table-data=zabbix.history_text \
--exclude-table-data=zabbix.history_uint \
--exclude-table-data=zabbix.history_uint_sync \
--exclude-table-data=zabbix.trends \
--exclude-table-data=zabbix.trends_uint
if [ $? -ne 0 ]
then
 rm "$BKUPDIR"/zabbix-db-`date +%Y%m%d`.sql
 alert zabbix "sql backup failed"
fi
log "Finish backup db"
}
#### main ####
pgdamp
archive
rotation-db
rotation-file
owner
