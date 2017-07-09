#!/bin/bash

# Plugin return codes
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

# Version
VERSION="1.1"

# Commands
CMD_BASENAME=$(which basename)
CMD_SNMPWALK=$(which snmpwalk)
CMD_GREP=$(which grep)
CMD_WC=$(which wc)

# Script name
SCRIPTNAME=`$CMD_BASENAME $0`


#Default variables
OID=".1.3.6.1.2.1.25.4.2.1"
HOST="127.0.0.1"
COMM="public"
PROCN="snmpd"
PARMS=""
STATE=$STATE_UNKNOWN
WARNING=0
CRITICAL=0
VERBOSE=0

print_usage() {
  echo "Usage: ./check_snmp_proc -H 127.0.0.1 -C public -N ssh -w 3 -c 0"
  echo "  $SCRIPTNAME -H ADDRESS"
  echo "  $SCRIPTNAME -C STRING"
  echo "  $SCRIPTNAME -N STRING"
  echo "  $SCRIPTNAME -w INTEGER"
  echo "  $SCRIPTNAME -c INTEGER"
  echo "  $SCRIPTNAME -h"
  echo "  $SCRIPTNAME -V"
}

print_version() {
  echo $SCRIPTNAME version $VERSION
  echo ""
  echo "This nagios plugins comes with ABSOLUTELY NO WARRANTY."
}

print_help() {
  print_version
  echo ""
  print_usage
  echo ""
  echo "Check the process by name via snmp"
  echo ""
  echo "-H ADDRESS"
  echo "   Name or IP address of host (default 127.0.0.1)"
  echo "-C STRING"
  echo "   Community name for the host SNMP agent (default public)"
  echo "-N PROCESS NAME"
  echo "   Exact process name (default snmpd)"
  echo "-P PROCESS PARMS" 
  echo "   Exact process parameters" 
  echo "-w INTEGER"
  echo "   Warning level of running processes (default: 0)"
  echo "-c INTEGER"
  echo "   Critical level of running processes (default: 0)"
  echo "-h"
  echo "   Print this help screen"
  echo "-v"
  echo "   Be verbose and print details of processes"  
  echo "-V"
  echo "   Print version and license information"
  echo ""
  echo "This plugin uses the 'snmpwalk' command included with the NET-SNMP package."
}


while getopts H:C:N:P:w:c:vh:Vh OPT
do
  case $OPT in
    H) HOST="$OPTARG" ;;
    C) COMM="$OPTARG" ;;
    N) PROCN="$OPTARG" ;;
    P) PARMS="$OPTARG" ;;
    w) WARNING=$OPTARG ;;
    c) CRITICAL=$OPTARG ;;
    h)
      print_help
      exit $STATE_UNKNOWN
      ;; 
    v) VERBOSE=1 ;;
    V)
      print_version
      exit $STATE_UNKNOWN
      ;;
   esac
done

#Plugin 
PROCN=${PROCN:0:15}
#CNT=`$CMD_SNMPWALK -v1 -On -c $COMM $HOST $OID | $CMD_GREP "\"$PROCN\"" | wc -l`

OUTPUT=`$CMD_SNMPWALK -v1  -OneqE -c $COMM $HOST $OID`
IFS=$'\n'
OIDLEN=${#OID}

#Arrays 
RUNINDEX=
RUNNAME=
RUNID=
RUNPATH=
RUNPARAMETERS=
RUNTYPE=
RUNSTATUS= 

for row in $OUTPUT 
do
	COLUMN=${row:$((${OIDLEN} + 1)):1}
	TRIM="${row:$((${OIDLEN} + 3)):${#row}}"
	IFS=" "
	set -- $TRIM
	INDEX="$1"
	TRIMMED="${TRIM:$((${#INDEX} + 1)):${#TRIM}}"
	if [[ ${TRIMMED:0:1} == '"' ]]; then
		TRIMMED="${TRIMMED:1}"
	fi 
	if [[ ${TRIMMED:$((${#TRIMMED} - 1)):1} == '"' ]]; then 
		TRIMMED="${TRIMMED:0:$((${#TRIMMED} - 1))}"
	fi 
	case $COLUMN in
		"1") RUNINDEX[$1]="$TRIMMED" ;;
		"2") RUNNAME[$1]="$TRIMMED" ;;
		"3") RUNID[$1]="$TRIMMED" ;;
		"4") RUNPATH[$1]="$TRIMMED" ;;
		"5") RUNPARAMETERS[$1]="$TRIMMED" ;;
		"6") RUNTYPE[$1]="$TRIMMED" ;;
		"7") RUNSTATUS[$1]="$TRIMMED" ;;
	esac  
done

RUNNING=
IDLING=
ZOMBIES=
INVALID= 
COUNTRUN=0
COUNTIDLE=0
COUNTZOMBIES=0 
COUNTINVALID=0

for i in "${RUNINDEX[@]}"
do
	if [[ "x${RUNNAME[$i]}x" == "x${PROCN}x" ]]; then  
		if [[ "x${PARMS}x" == x""x ]] || [[ "x${RUNPARAMETERS[$i]}x" == "x${PARMS}x" ]]; then 
			
			[[ ${RUNSTATUS[$i]} -eq 1 ]] && COUNTRUN=$(($COUNTRUN + 1)) && RUNNING[$COUNTRUN]=$i
			[[ ${RUNSTATUS[$i]} -eq 2 ]] && COUNTIDLE=$(($COUNTIDLE + 1)) && IDLING[$COUNTIDLE]=$i 
			[[ ${RUNSTATUS[$i]} -eq 3 ]] && COUNTZOMBIES=$(($COUNTZOMBIES + 1)) && ZOMBIES[$COUNTZOMBIES]=$i
			[[ ${RUNSTATUS[$i]} -eq 4 ]] && COUNTINVALID=$(($COUNTINVALID + 1)) && INVALID[$COUNTZOMBIES]=$i
			[[ $VERBOSE -eq 1 ]] && echo "PID $i (${RUNNAME[$i]}) ID: ${RUNID[$i]} : ${RUNPATH[$i]} ${RUNPARAMETERS[$i]} - Type: ${RUNTYPE[$i]} Status: ${RUNSTATUS[$i]}"
			
		fi
	fi 
done  

CNT=$((${#RUNNING[@]} + ${#IDLING[@]} - 2))
if [ $CNT  -eq 0 ]; then
	STATE=$STATE_CRITICAL
	DESCRIPTION="PROC CRITICAL: Process $PROCN ($PARMS) does not exist"
elif [ $CNT -le $WARNING ]; then
	STATE=$STATE_WARNING
	DESCRIPTION="PROC WARNING: Running only $CNT instances of $PROCN"
elif [ $CNT -le $CRITICAL ]; then
       STATE=$STATE_CRITICAL
	DESCRIPTION="PROC CRITICAL: Running only $CNT instances of $PROCN"
else
	STATE=$STATE_OK
	DESCRIPTION="PROC OK: $PROCN ($PARMS) exist. Running instances: $CNT"
fi

#Perfadata
DESCRIPTION="$DESCRIPTION | count=$CNT;$WARNING;$CRITICAL"

#Longtext
TEXT= 
if [ $COUNTINVALID -gt 0 ]; then
        TEXT="${TEXT}Invalid: "
        SUBTEXT=
        for proc in "${INVALID[@]}"
        do
                SUBTEXT="${SUBTEXT},$proc"
        done
        TEXT="${TEXT}${SUBTEXT:2};\n"
fi

if [ $COUNTZOMBIES -gt 0 ]; then
        TEXT="${TEXT}Not runable: "
        SUBTEXT=
        for proc in "${ZOMBIES[@]}"
        do
                SUBTEXT="${SUBTEXT},$proc"
        done
        TEXT="${TEXT}${SUBTEXT:2};\n"
fi

if [ $COUNTIDLE -gt 0 ]; then 
	TEXT="${TEXT}Idle: "	
	SUBTEXT=
	for proc in "${IDLING[@]}"
	do
        	SUBTEXT="${SUBTEXT},$proc"
	done
	TEXT="${TEXT}${SUBTEXT:2};\n" 
fi 

if [ $COUNTRUN -gt 0 ]; then
        TEXT="${TEXT}Running: "
        SUBTEXT=
        for proc in "${RUNNING[@]}"
        do
                SUBTEXT="${SUBTEXT},$proc"
        done
        TEXT="${TEXT}${SUBTEXT:2};\n"
fi

DESCRIPTION="$DESCRIPTION\n$TEXT" 






#Perfadata
DESCRIPTION="$DESCRIPTION | count=$CNT;$WARNING;$CRITICAL idle=$COUNTIDLE running=$COUNTRUN"


echo -e $DESCRIPTION
exit $STATE
