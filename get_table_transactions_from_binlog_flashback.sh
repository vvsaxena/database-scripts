#!/bin/sh
#### Change the binary log file appropriately and if you want to start from a certain log position or timestamp then you can edit that part.
FL=/st_mysql_na02nfs_t01/db/data-restore-test-data/mysqld-bin.000003
mysqlbinlog  --base64-output=DECODE-ROWS --verbose $FL > tempbinlog
#./mariadb-mysqlbinlog --start-position=4657 --base64-output=DECODE-ROWS --verbose $FL > tempbinlog
. /db/scripts/Utils.sh
declare -A recovery_files_order
### Now search for line numbers where transactions related to table : metastorage appears
while read line
do
        ### For each line number prints the previous line also which has the pattern of # at logposition
        #awk '{ if(NR >= '$(($line - 5))' && NR <= '$line') print }' tempbinlog|grep "^# at"|sed -n '$p'
        str=$(awk '{ if(NR >= '$(($line - 1))' && NR <= '$line') print }' tempbinlog)
        #echo "$str"
        #### Now get the log position of last "# at lo position" statement , this should be the starting log position of that transaction
        stpos=$(echo "$str"|grep "^# at"|sed -n '$p'|awk '{print $3}')
        #### Now since we have starting log position , try to get where COMMIT appears and print 2 lines before of COMMIT to get the ending log position
        ### We have to take the first "# at log position" pattern , assuming that whole transaction will fit in next 1000 rows , trying to grab 1000 rows
        ### After the starting position and finding commit with 2 lines before it where the log positions usually appears for COMMIT
        #endpos=$(grep -A1000 "# at $stpos" tempbinlog|grep -B2 "^COMMIT"|grep "^# at"|sed -n '1,1p'|awk '{print $3}')
        ### New and more cleaner way to find next commit
        endpos=$(sed -n "/# at $stpos/,/COMMIT\/\*\!\*\//p" tempbinlog|grep -B2 "^COMMIT"|grep "^# at"|sed -n '1,1p'|awk '{print $3}')
        echo "---------------------------------------------------------------------------------------------------------------------------------------"
        echo "Start pos : $stpos        End PosL $endpos"
        #### Putting SQL readable code in review file first
        ./mariadb-mysqlbinlog --base64-output=DECODE-ROWS --verbose --start-position=$stpos --stop-position=$endpos $FL > ${stpos}_${endpos}_review.sql
        ### Preparing the individual transaction flashback file , if review looks good then these recovery files needs to be applied in reverse order
        ./mariadb-mysqlbinlog --flashback --start-position=$stpos --stop-position=$endpos $FL > ${stpos}_${endpos}_recovery.sql
        ### Adding recovery file to array
        addelementtoarray recovery_files_order "${stpos}_${endpos}_recovery.sql"
done <<< "$(awk '/(.*Table_map: .*metastorage*)/ { print NR }' tempbinlog)"
#####Getting rollback sequence by reversing the order of recovery files needs to be applied
rollbackSeq=$(echo "${recovery_files_order[*]}"|tr ' ' '\n'|tac)
echo "$rollbackSeq" |while read sqlFile
do
        line1
        echo "Applying ...$sqlFile..."
        echo "mysql -uroot -p -h hostname < ./$sqlFile"
done
