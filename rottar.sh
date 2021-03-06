#!/bin/bash
#
# Run a system backup.
# Full backups run on Monday, incremental on every other day of the week.
# Incremental backups run Tue-Sun and are recycled every 6 days.  Full
# backup tapes are rotated every 5 weeks.  Example backup rotation schedule:
#
#     SUN    MON    TUE    WED    THU    FRI    SAT
#            A      1      2      3      4      5
#     6      B      1      2      3      4      5
#     6      C      1      2      3      4      5
#     6      D      1      2      3      4      5
#     6      A
#
# The lettered tapes are full backups, the numbered tapes are incremental.
# This schedule can scale to an arbitrary number of weeks as necessary.
#
# NOTE:  Loss of the listed incremental status file in /var/lib/tar will
# trigger a new full backup, in which case the schedule should be altered
# and the full backup rotation day shifted.
#
# Copyright (C) 2010 David Cantrell <david.l.cantrell@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# Settings

# Tape device
TAPEDEV="/dev/st0"

# Paths to back up
BACKUP_INCLUDE="/bin /boot /etc /home /lib /lib64 /opt /root /sbin /usr /var"

# Paths to exclude (e.g., subdirectories in BACKUP_INCLUDE)
BACKUP_EXCLUDE=

# Full backup tape letter range (e.g., min of A and max of D would have
# four tapes in the full backup rotation)
MIN_FULL_VOL="A"
MAX_FULL_VOL="B"

# Full backup day
FULL_BACKUP_DAY="Mon"


### MAIN ###

PATH=/bin:/usr/bin
TARDB=/var/lib/tar

DAYOFWEEK="$(date +%a)"
STAMP="$(date +%d-%b-%Y)"
LISTED_INCR="${TARDB}/listed-incremental.$(hostname)"
CURR_INCR_TAPE="${TARDB}/curr_incremental_tape"
CURR_FULL_TAPE="${TARDB}/curr_full_tape"

if [ ! -r ${TAPEDEV} ]; then
    echo "${TAPEDEV} does not exist." >&2
    exit 1
fi

if [ ! -d "${TARDB}" ]; then
    mkdir -p "${INCRDR}"
fi

if [ "${DAYOFWEEK}" = "${FULL_BACKUP_DAY}" ]; then
    t="Full"
    CURR_FILE="${CURR_FULL_TAPE}"
    if [ -f "${CURR_FULL_TAPE}" ]; then
        curr="$(cat ${CURR_FULL_TAPE} | tr -d "\n" | od -An -t dC)"
        max="$(echo "${MAX_FULL_VOL}" | tr -d "\n" | od -An -t dC)"

        if [ "${curr}" = "${max}" ]; then
            NEEDED_TAPE="${MIN_FULL_VOL}"
        else
            next="$(expr ${curr} + 1)"
            NEEDED_TAPE="$(awk -v char=${next} 'BEGIN { printf "%c\n", char; exit }')"
        fi
    else
        NEEDED_TAPE="${MIN_FULL_VOL}"
    fi
else
    t="Incremental"
    CURR_FILE="${CURR_INCR_TAPE}"
    if [ -f "${CURR_INCR_TAPE}" ]; then
        NEEDED_TAPE="$(expr $(cat ${CURR_INCR_TAPE}) + 1)"
    else
        NEEDED_TAPE="1"
    fi
fi

EXCLUDE_LIST="$(mktemp -t exclude-list.XXXXXXXXXX)"
echo "${LISTED_INCR}" > ${EXCLUDE_LIST}
find /var -type s >> ${EXCLUDE_LIST}

echo "Insert tape \"${t} ${NEEDED_TAPE}\""
echo -n "Press Enter to begin ${t} backup for ${STAMP}..."
read JUNK

if [ "${t}" = "Full" ]; then
    echo
    echo -n ">>> Forcing full backup by removing listed incremental db..."
    rm -f ${LISTED_INCR} ${CURR_INCR_TAPE}
    echo "done."
fi

echo
echo -n ">>> Erasing tape \"${t} ${NEEDED_TAPE}\"..."
mt -f ${TAPEDEV} erase
echo "done."

echo
echo ">>> Running tar..."
tar -c -v -f ${TAPEDEV} -g ${LISTED_INCR} \
    -X ${EXCLUDE_LIST} \
    --acls --selinux --xattrs --totals=SIGUSR1 \
    ${BACKUP_INCLUDE} 2> ${TARDB}/tar.stderr
rm -f ${EXCLUDE_LIST}

echo
echo -n ">>> Recording current tape in use..."
echo "${NEEDED_TAPE}" > ${CURR_FILE}
echo "done."

echo
echo -n ">>> Rewinding and ejecting tape \"${t} ${NEEDED_TAPE}\"..."
mt -f ${TAPEDEV} offline
echo "done."
