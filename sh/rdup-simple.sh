#!/bin/bash

# updates a hardlinked backup
# licensed under the GPL version 3
# Copyright Miek Gieben, 2007 - 2008

prefix=@prefix@
datarootdir=@datarootdir@
exec_prefix=@exec_prefix@
datadir=@datadir@/rdup
sysconfdir=@sysconfdir@/rdup
lockdir=/var/lock
GNU_DEFS=rdup-snapshot.gnu

# common stuff
if ! source $datadir/shared.sh; then
	# no _echo2
	echo ** $0: Failed to source $datadir/shared.sh >&2
	exit 1
fi


usage() {
        cat << HELP
$PROGNAME [+N] DIR [DIR ...] DEST

This is a wrapper around rdup and rdup-snap

DIR  - directories to back up
+N   - Look N days back for previous backups, defaults to 8
       hours when using -H
DEST - where to store the backup. This can be:
	ssh://user@host/directory (note: no colon after the hostname
	ssh://host/directory
	file:///directory (note: 3 slashes)
	/directory
	directory

OPTIONS:
 -k KEYFILE encrypt all files, using mcrypt (rdup-crypt)
 -g	    encrypt all files, using gpg (rdup-gpg)
 -z         compress all files, using gzip (rdup-gzip)
 -E FILE    use FILE as an exclude list
 -H         perform hourly backups
 -f         force a full dump
 -v         echo the files processed to stderr
 -x         pass -x to rdup
 -h         this help
 -V         print version
HELP
}

PROGNAME=$0
NOW=`date +%Y%m/%d`
c=""
ssh=""
pipe=""
l="-l"
enc=false
etc=~/.rdup
force=false
hour=""
DAYS=8

while getopts "E:k:vfgzxahHV" o; do
        case $o in
		E)
                if [[ -z "$OPTARG" ]]; then
                        _echo2 "-E needs an argument"
                        exit 1
                fi
                E="-E $OPTARG"
                ;;
                k)
                if [[ -z "$OPTARG" ]]; then
                        _echo2 "-k needs an argument"
                        exit 1
                fi
                if [[ ! -r "$OPTARG" ]]; then
                        _echo2 "Cannot read keyfile \`$OPTARG': failed"
                        exit 1
                fi
                pipe="$pipe | @bindir@/rdup-crypt $OPTARG"
		if $enc; then
			_echo2 "Encryption already set"
			exit 1
		fi
		enc=true
                c="-c"
                ;;
                z) pipe="$pipe | @bindir@/rdup-gzip"
		if $enc; then
			_echo2 "Select compression first, then encryption"
			exit 1
		fi
                c="-c"
                ;;
		g) pipe="$pipe | @bindir@/rdup-gpg"
		if $enc; then
			_echo2 "Encryption already set"
			exit 1
		fi
		enc=true
		c="-c"
		;;
                f) force=true;;
                a) ;;
                v) OPT="$OPT -v";;
                x) x="-x";;
                H) NOW=`date +%Y%m/%d/%H`;hour="-H";;
                h) usage && exit;;
                V) version && exit;;
                \?) _echo2 "Invalid option: $OPTARG"; exit 1;;
        esac
done
shift $((OPTIND - 1))

if [[ ${1:0:1} == "+" ]]; then
        DAYS=${1:1}
        if [[ $DAYS -lt 1 || $DAYS -gt 99 ]]; then
                _echo2 "+N needs to be a number [1..99]"
                exit 1
        fi
        shift
else
        DAYS=8
fi

if [[ $# -eq 0 ]]; then
	usage
	exit
fi

i=1; last=$#; DIRS=
while [[ $i -lt $last ]]; do
	DIRS="$DIRS $1"
	shift
	((i=$i+1))
done
# rdup [options] source destination
#dest="ssh://elektron.atoom.net/directory"
#dest="ssh://elektron.atoom.net/directory/var/"
#dest="file:///var/backup"
#dest="/var/backup"
#dest="ssh://miekg@elektron.atoom.net/directory"

dest=$1
if [[ ${dest:0:6} == "ssh://" ]]; then
	rest=${dest/ssh:\/\//}
	u=`echo $rest | cut -s -f1 -d@`
	rest=${rest/$u@/}
	h=`echo $rest | cut -s -f1 -d/`

	BACKUPDIR=${rest/$h/}

	c="-c"
	l=""	# enable race checking in rdup
	if [[ -z $u ]]; then
		ssh=" ssh -x $h"
	else
		ssh=" ssh -x $u@$h"
	fi
fi
if [[ ${dest:0:7} == "file://" ]]; then
	rest=${dest/file:\/\//}
	BACKUPDIR=$rest
fi
if [[ ${dest:0:1} == "/" ]]; then
	BACKUPDIR=$dest
fi

# no hits above, assume relative filename
if [[ -z $BACKUPDIR ]]; then
	BACKUPDIR=`pwd`/$dest
fi

# change all / to _ to make a valid filename
IDENT=$(echo $dest | sed 's/\/\/*/_/g')
STAMP=$etc/timestamp.$HOSTNAME_$IDENT
LIST=$etc/list.$HOSTNAME_$IDENT

create_rdup $etc

# create our command line
if [[ -z $ssh ]]; then
        pipe="$pipe | ${exec_prefix}/bin/rdup-snap $c $OPT -b $BACKUPDIR/$NOW"
else
        pipe="$pipe | $ssh rdup-snap $c $OPT -b $BACKUPDIR/$NOW"
fi
cmd="${exec_prefix}/bin/rdup $E $x $l $c -N $STAMP $LIST $DIRS $pipe"

if ! $force; then
        if [[ -z $ssh ]]; then
                ${exec_prefix}/bin/rdup-snap-link $hour $DAYS $BACKUPDIR $NOW
                purpose=$?
        else
                $ssh "rdup-snap-link $hour $DAYS $BACKUPDIR $NOW"
                purpose=$?
        fi
else
        purpose=1
fi
case $purpose in
        0) _echo2 "INCREMENTAL DUMP" ;;
        1)
        _echo2 "FULL DUMP"
        rm -f $LIST
        rm -f $STAMP ;;
        *)
        _echo2 "Illegal return code from rdup-snap-link"
        exit 1 ;;
esac
# execute the backup command
#_echo2 "Executing: ${cmd}"
eval ${cmd}