#!/bin/sh
#### Purpose of this script is to backup the databases , it runs percona xtrabackup and creates one tar file after compression
#### in /backup directory which is NFS. Compression is needed to encrypt the data since NFS storage is not encrypted.
### Written By Vishal Saxena: 04/20/2018

compress_backup()
{
#find $backupdir -type f -ls|awk '{print $11}'|while read fyle
#do
#PASSKEY=$(mysql -u ${USER} -p${PASS} -e "select * from utilities.passkey\G"|grep "keyname"|cut -d: -f2,2|tr -d ' ') || exit 1;

        echo "$PASSKEY"|/bin/gpg -c --passphrase-fd 0 --batch ${backupdir}-${binInfo}.tar

        if [ $? -ne 0 ]
        then
                echo "Compress failed with gpg...."
                compress_status=1
        else
                echo "Compress succeeded..."
                rm ${backupdir}-${binInfo}.tar

        fi

#done
}

runPreCheck() {
####Checking for backup NFS mount
df -h|grep "\/backup"
if [ $? -ne 0 ]
then
        echo "$HST:Database dump Pre check failed....\/backup is not mounted"|/bin/mailx -s"backup failed for mysql DB" -S smtp=$smtpHost $email
        exit 1
fi
#####Checking if /backup is read-write or not
touch /backup/t
if [ $? -ne 0 ]
then
        echo "$HST:Database dump Pre check failed...\/backup is read only"|/bin/mailx -s"backup failed for mysql DB" -S smtp=$smtpHost $email
        exit 1
fi
####Now checking for /db
df -h|grep "\/db"
if [ $? -ne 0 ]
then
        echo "$HST:Database dump Pre check failed....\/db is not mounted"|/bin/mailx -s"backup failed for mysql DB" -S smtp=$smtpHost $email
        exit 1
fi
#####Checking if /backup is read-write or not
touch /db/t
if [ $? -ne 0 ]
then
        echo "$HST:Database dump Pre check failed...\/db is read only"|/bin/mailx -s"backup failed for mysql DB" -S smtp=$smtpHost $email
        exit 1
fi
}

log_to_syslog() {
logMsg=$1
logPat=$(date "+%Y-%m-%d %H:%M:%S "`hostname`)
echo "$logPat mysql:db:backup $logMsg" >> /db/logs/na02lstxdbp05-mysqld.log
echo "$logPat mysql:db:backup $logMsg"
}

update_db() {
lstatus=$1
lhost=$(hostname -f)
echo "update utilities.node_status set status=\"$lstatus\" where node_name=\"$lhost\";"|mysql --login-path=healthcheck --database utilities
}

###### Main starts here
### This script is used to sync the 2 async slaves in PHX
## First dump the mysql using this script and apply log
### Then transfer the "backupdir" to correct data volumne on async slaves
smtpHost=na02lmtap01.prod-us.alarm.com
email=$(cat /db/group_email)
HST=$(hostname -f)
compress_status=0
ulimit -n 1048576
dtpat=$(date +%m%d%Y%H%M%S)
mkdir -p $backupdir/$dtpat
backupdir=/backup/${dtpat}-mysql-xtrabackup
logdir=/backup/logs
mkdir -p $logdir
. /db/.mysqlpass
#########################################################################
echo "Running Pre checks like /backup is mounted and not read only"
runPreCheck
echo "Starting backup..."
#### Setting the false flag in node_Status table , so a successfull backup should change that later
update_db "Backup Failed"
echo "node_dump_status{} 1.5" > /backup/db-prom-collect/dumpStatus.prom
echo "{ \"dump_status\": 1.5 }" > /backup/db-file-collector/wavefront/dump_status.json
echo "*******************************************************************"
date
echo "*******************************************************************"
innobackupex --login-path=mysqlbackup --parallel=5 --galera-info --datadir=/var/lib/mysql --no-timestamp --stream=tar ./ > ${backupdir}.tar 2>$logdir/${dtpat}_xtrabackup.log

###Logging xtrabackup output to syslog for sumologic upload
SUMOPAT=$(hostname):db:backup
logger -t "$SUMOPAT" -f $logdir/${dtpat}_xtrabackup.log
#log_to_syslog $logdir/${dtpat}_xtrabackup.log

###Verifying backup and writing to syslog
if tail -1 $logdir/${dtpat}_xtrabackup.log | grep -q "completed OK"; then
    log_to_syslog "Backup successful!"
    update_db "Backup Success"
    echo "node_dump_status{} 2" > /backup/db-prom-collect/dumpStatus.prom
    echo "{ \"dump_status\": 2 }" > /backup/db-file-collector/wavefront/dump_status.json
else
    log_to_syslog "Backup failure! Check log file for more information"
    update_db "Backup Failed"
    echo "node_dump_status{} -1" > /backup/db-prom-collect/dumpStatus.prom
    echo "{ \"dump_status\": -1 }" > /backup/db-file-collector/wavefront/dump_status.json
fi
###############################################

#if grep "completed OK" $logdir/${dtpat}_xtrabackup.log > /dev/null
if [ $? -eq 0 ]
then
        echo "Backup completed successfully..."
        echo "****************************************************"
        echo "Extracting the binary log file and position from xtrabackup_binlog_info"
        binInfo=$(tar xf ${backupdir}.tar xtrabackup_binlog_info -O|awk '{print $1"."$2}')
        mv ${backupdir}.tar ${backupdir}-${binInfo}.tar
        date
        echo "****************************************************"
        echo "Compressing the backup..."
        compress_backup
        echo "****************************************************"
        date
        echo "******* Backup compression finished*****************************************"
        echo "node_dump_status{} 1" > /backup/db-prom-collect/dumpStatus.prom
        echo "{ \"dump_status\": 1 }" > /backup/db-file-collector/wavefront/dump_status.json
else
        echo "$HST:Backup failed...Please check $backupdir"|/bin/mailx -s"backup failed for mysql DB" -S smtp=$smtpHost $email
        echo "node_dump_status{} -1" > /backup/db-prom-collect/dumpStatus.prom
        echo "{ \"dump_status\": -1 }" > /backup/db-file-collector/wavefront/dump_status.json
        exit 1
fi
####### Checking for compression failure
if [ $compress_status -eq 1 ]
then
        echo "$HST: compression failed....Please check $backupdir"|/bin/mailx -s"backup failed for mysql DB" -S smtp=$smtpHost $email
fi
##################################################################
echo ""
echo "Deleting Old Files"
find /backup/ -name \*.gpg -a -mtime +31 -exec rm {} \;
find /backup/logs -name \*.log -a -mtime +31 -exec rm {} \;
##########################################################################
echo "Finished backup..."
echo "*******************************************************************"
date
echo "*******************************************************************"
