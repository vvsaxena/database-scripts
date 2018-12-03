function blue() {
    echo -e "\x1b[34m\x1b[1m"$@"\x1b[0m";
}

function green() {
    echo -e "\x1b[32m\x1b[1m"$@"\x1b[0m";
}

function red() {
    echo -e "\x1b[31m\x1b[1m"$@"\x1b[0m";
}

push_stack_messages () {
    stack="$stack
$1"
    stack_trace=$stack
}

uc () { echo "$*" | tr '[:lower:]' '[:upper:]' ; }
lc () { echo "$*" | tr '[:upper:]' '[:lower:]' ; }
subst () { echo "${1%%$2*}$3${1#*$2}" ; }
strlen() { x=$*; echo ${#x};}

##The first part removes all tabs (\t) and spaces, and the second part removes all empty lines
rmallspaces() { echo "$*"|sed -e 's/[\t ]//g;/^$/d'; }

seek_confirmation() {
  printf "\n${bold}$@${reset}"
  read -p " (y/n) " -n 1
  printf "\n"
}

# Test whether the result of an 'ask' is a confirmation
is_confirmed() {
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
  return 0
fi
return 1
}

log() {
   echo -e "$(date +%m.%d_%H:%M) $@"| tee -a $OUTPUT_LOG
}
line1() {
echo "========================================================================================================================================================="
}
line2() {
echo "*********************************************************************************************************************************************************"
}
line3() {
echo "---------------------------------------------------------------------------------------------------------------------------------------------------------"
}
line4() {
echo "_________________________________________________________________________________________________________________________________________________________"
}
#######Handling arrays
# void addelementtoarray (string <array_name>, string <element>, ...)
#
function addelementtoarray {
    local R=$1 A
    shift

    for A; do
        eval "$R[\${#$R[@]}]=\$A"
    done

    # Or a one liner but more runtime expensive with large arrays since all elements will always expand.
    # In this method also, all element IDs are reset starting from 0.
    # Maybe this is also what you need since the IDs here does not need to be sorted.  A problem may occur on the former if an ID exist that is higher than the number of elements.
    # Only that it resets all IDs everytime.
    # eval "$1=(\"\${$1[@]}\" \"${2:@}\")"
}

##array=()
##addelementtoarray array a "b " "c d"
##addelementtoarray array 1 2 3 4
#addelementtoarray different_array 1 2 3 4   # works safely with method 2
##echo "${array[2]}"
get_dbs() {
##Usage: get_dbs localhost
mysql --login-path=healthcheck --skip-column-names -h $1 -e"show databases"|sort
}
get_tbls() {
###Usage: get_tbls 172.20.0.213 altx_sandbox
mysql --login-path=healthcheck --skip-column-names --database $2 -h $1 -e"show tables"|sort
}
get_stps() {
###Usage : get_stps localhost utilities
mysql --login-path=healthcheck --skip-column-names --database $2 -h $1 -e"SHOW PROCEDURE STATUS WHERE db=\"$2\""
}
get_vws() {
###USage: get_vws localhost altx_sandbox
mysql --login-path=healthcheck --skip-column-names --database $2 -h $1 -e"SHOW FULL TABLES IN $2 WHERE TABLE_TYPE LIKE 'VIEW';"
}
get_trgs() {
###USage: get_trgs localhost altx_sandbox
mysql --login-path=healthcheck --skip-column-names --database $2 -h $1 -e"SHOW TRIGGERS IN $2 ;"
}
get_time_ms() {
ts=$(date +%s%N) ; $@ ; tt=$((($(date +%s%N) - $ts)/1000000)) ; echo "Time taken: $tt milliseconds"
}
