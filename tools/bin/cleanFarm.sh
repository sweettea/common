#!/bin/bash
# Script to clean up farms and release them
# $Id$


set -e #exit on error

function usage () {
    cat << END
cleanFarm is a utility for cleaning up farms, with prejudice. It will try
checkServer fix, removing from maintenance, and cleanAndRelease. If this
can't clean it up, you actually have some work on your hands.

-m if set, will attempt to get a farm out of maintenance (or not,
   if the farm is not in maintenance) and release it
   (defaults to false)
-u the user who owns the farm. If not set, will assume you own it.
END
exit 255
}


#############################################################################
# Collect our options and set the values for use
##
while getopts "mu:h" option; do
    case "$option" in
        m )      maintenance="yes"      ;;
        u )      user=$OPTARG           ;;
        h|* )    usage                  ;;
    esac
done

shift $(($OPTIND - 1))

#############################################################################
# Do some basic checks so we don't completely screw something up
##

function checkOwnership() {
    for farm in $*; do
        getOwner $farm
        reserveUnowned $farm
        if [[ $owner && "$user" == "" ]] ; then
            # owned machine and user is self
            matches=$(rsvpclient list --mine | grep $farm | wc -l)
            if [[ $matches -ne "1" ]] ; then
                echo "$owner owns $farm."\
                    "If you really meant to clean this" \
                    "farm, please specify the owner with the -u option."
                return 1
            fi
        elif [[ $owner && "$owner" == "$user" ]] ; then
            # owned by the specified user. Will clean
            return 0
        elif [[ ! $owner ]] ; then
            # unowned. Will clean
            return 0
        else
            echo "$owner owns this farm. You specified $user. " \
                "If you really meant to clean this farm, please " \
                "specify the correct user with the -u option."
            return 1
        fi
    done
}

function checkMaintenance() {
    # if we don't specify maintenance, don't clean farms in maintenance
    if [[ ! $maintenance ]] ; then
        for farm in $*; do
            match=$(rsvpclient list --class MAINTENANCE | grep $farm | wc -l)
            if [[ $match -ne "0" ]] ; then
                echo "Farm $farm is in maintenance and -m flag is not specified." \
                     " If you really meant to clean this farm, please specify" \
                     " the maintenance option."
                return 1
            fi
        done
    fi
}


function reserveUnowned () {
    local f=$1
    local opts=""
    if [[ $maintenance ]]; then
        opts="--resource"
    fi
    if [[ -n $user ]]; then
        opts="$opts --user $user"
    fi
    if [[ ! $owner ]]; then
        echo "Reserving farm $f prior to cleaning"
        rsvpclient rsvp $opts $f
    fi
}

function removeFromMaintenance() {
    if [[ $maintenance ]] ; then
        echo "Handling farms in maintenance"
        for farm in $*; do
            rsvpclient modify $farm --del MAINTENANCE --add ALL
        done
    fi
}

function checkServerFix () {
    echo "Running checkServer --fix"
    for farm in $*; do
        if [[ "$user" == "" ]] ; then
            ssh $farm sudo checkServer.pl --fix
        else
            ssh $farm sudo checkServer.pl --fix --user $user
        fi
    done
}

function cleanAndRelease () {
    echo "Running clean and release"
    if [[ "$user" == "" ]] ; then
        cleanAndRelease.pl --force $*
    else
        cleanAndRelease.pl -u $user --force $*
    fi
}

function release () {
    echo "Releasing the cleaned farms"
    if [[ "$user" == "" ]] ; then
        rsvpclient release $*
    else
        rsvpclient release --user $user $*
    fi
}

function getOwner () {
    local f=$1
    echo "Checking ownership of $f"
    owner=""
    nomaint=$(rsvpclient list | grep "^$f" | awk '{print $2}')
    maint=$(rsvpclient list --class MAINTENANCE | grep $f | awk '{print $2}')
    if [[ $nomaint ]] ; then
        owner=$nomaint
    elif [[ $maint ]] ; then
        owner=$maint
    fi
}

function main () {
    checkMaintenance $*
    checkOwnership $*
    checkServerFix $*
    removeFromMaintenance $*
    checkServerFix $* #have to run twice to fix classes
    cleanAndRelease $*
    release $* &>/dev/null
}

main $*
