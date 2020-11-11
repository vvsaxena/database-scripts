#!/bin/sh
extract_first_column_each_table() {
MYSQL="mysql --login-path=healthcheck -h <host ip> --database $MAINDB --skip-column-names"

$MYSQL -e"show full tables where table_type='BASE TABLE'"|awk '{print $1}'|while read TBL
do
        firstCol=$($MYSQL -e"desc $TBL;"|head -1|awk '{print $1}')
        echo "$TBL $firstCol"

done > $tempDir/no_primary_key_id_tables

}

process_nonid_tables() {
MYDB=$1
MYTBL=$2

if grep "^$MYTBL" $tempDir/no_primary_key_id_tables > /dev/null
then
        MYCOL=$(grep -w "^$MYTBL" $tempDir/no_primary_key_id_tables|awk '{print $2}')
else
        echo "ERROR : No column found in $tempDir/no_primary_key_id_tables for Table $MYTBL ..."
fi

echo "******************** for $MYDB.$MYTBL *************************************"

        totalrecCount=$(grep "$localPat" $tempDir/allUpdates.sql|wc -l|awk '{print $1}')

        start=1

        while [ $start -le $totalrecCount ]
        do
                nextLine=`expr $start + $chunk`
                echo "From Lines $start to $nextLine ...."
                idList=$(grep "$localPat" $tempDir/allUpdates.sql|sed -n "${start},${nextLine}"p|cut -d: -f2,2|tr '\n' ','|sed "s/,$//g")
                echo "Syncing to $sendToMysql "
                echo "DELETE FROM $MYTBL where $MYCOL in ($idList) ; "|$sendToMysql

                if [ $? -ne 0 ]
                then
                        echo "DELETE Failed ...."
                else
                        echo "DELETE SUCCEEDED ..."
                fi

                CMD=$(echo "mysqldump --login-path=admin -h <host IP > --no-create-info --default-character-set=utf8mb4 --where \"$MYCOL in ($idList)\"  $MYDB $MYTBL|$sendToMysql")
                eval "$CMD"

                if [ $? -ne 0 ]
                then
                        echo "MYSQLDUMP insert Failed ...."
                else
                        echo "MYSQLDUMP SUCCEEDED ..."
                fi

                start=`expr $nextLine + 1`
        done
}

process_id_tables() {
localPat=$1
MYDB=$(echo "$localPat"|cut -d. -f1,1|tr -d '`')
MYTBL=$(echo "$localPat"|cut -d. -f2,2|tr -d '`')

if grep -w $MYTBL no_primary_key_id_tables > /dev/null
then
        process_nonid_tables $MYDB $MYTBL
else

        echo "******************** for $MYDB.$MYTBL *************************************"

        totalrecCount=$(grep "$localPat" $tempDir/allUpdates.sql|wc -l|awk '{print $1}')

        start=1

        while [ $start -le $totalrecCount ]
        do
                nextLine=`expr $start + $chunk`
                echo "From Lines $start to $nextLine ...."
                idList=$(grep "$localPat" $tempDir/allUpdates.sql|sed -n "${start},${nextLine}"p|cut -d: -f2,2|tr '\n' ','|sed "s/,$//g")
                echo "Syncing to $sendToMysql "
                echo "DELETE FROM $localPat where id in ($idList) ; "|$sendToMysql
                echo "mysqldump --login-path=admin -h <host ip> --no-create-info --default-character-set=utf8mb4 --where \"id in ($idList)\"  $MYDB $MYTBL"|$sendToMysql
                start=`expr $nextLine + 1`
        done
fi

}

processUpdates() {
cat $tempDir/allUpdates.sql|awk '{print $2}'|uniq|while read dbTable
do
        mypat=$(echo "$dbTable"|sed 's/`/\\`/g')
        LDB=$(echo "$dbTable"|cut -d. -f1,1|tr -d '`')
        LTBL=$(echo "$dbTable"|cut -d. -f2,2|tr -d '`')
        process_nonid_tables $LDB $LTBL
        
done
}

##################Main starts here
### This script scan the binary log and prints the delete and mysqldump generated inserts to recover or resync tables for a specific database and table
#### However this only works for tables having primary key as id for now.
####Planning to add more tables having different primary keys
MAINDB=$1
MAINTBL=$2
binfile=$3
chunk=$4
tempDir=/db/archive
sendToMysql="mysql --login-path=scriptadmin -h 127.0.0.1 --database $MAINDB"
echo "Extracting Table/columns definitions ..."
extract_first_column_each_table

MYSQLBNLOG="mysqlbinlog --base64-output=DECODE-ROWS -d $MAINDB --verbose "

#######Extracting inserts
echo "Extracting ...inserts,updates,deletes ..."

$MYSQLBNLOG $binfile|egrep -A2 "^### INSERT.*|^### UPDATE.*|^### DELETE.*"|egrep -v "^### SET|^### WHERE|^--"|tr '\n' ' '|sed "s/### INSERT INTO/\nINSERT/g;s/### UPDATE/\nUPDATE/g;s/### DELETE FROM/\nDELETE/g;s/###   @1=/:/g"|grep -v "^$" >  $tempDir/allTableUpdates.sql

totalFieldsCount=$(awk '{print NF}' $tempDir/allTableUpdates.sql|sort -n|uniq)

if [ $totalFieldsCount -eq 3 ]
then
        echo "File $tempDir/allTableUpdates.sql looks good and contain 3 columns only ...proceeding ..."

        cat $tempDir/allTableUpdates.sql|awk '{print $2}'|sort|uniq|cut -d. -f2,2|tr -d '`'|while read echTbl
        do
                echo "===========================Working for $echTbl ======================================"
                grep -w "\`$MAINDB\`.\`$echTbl\`" $tempDir/allTableUpdates.sql|sort -k2,2 |uniq > $tempDir/allUpdates.sql
                processUpdates
        done
else
        echo "ERROR: File $tempDir/allUpdates.sql1 does not look ok ...Exiting "
        exit
fi
###########################################################################################################
