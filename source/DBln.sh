#!/bin/bash

IFS=$'\n'

PROG="$0"


function usage()
{
    echo "USAGE:  $PROG [-h] [ln-opts] DB... DEST"
} >&2


function print_help()
{
    usage
    echo
    echo 'Create links to DB(s) at DEST using ln. Also hidden DB files will be linked.'
    echo 'Warning: hidden files created after linking on either the original DBs or the'
    echo 'links are not affected by this tool.'
} >&2


function error()
{
    echo "$PROG: error: $@"
} >&2


function parse_args()
{
    if (( $# == 0 ));
    then
        error "missing arguments"
        usage
        exit 1
    fi

    if [[ "$1" == "-h" ]];
    then
        print_help
        exit 0
    fi

    LNOPTS=()
    ARGS=()
    while (( $# > 0 ));
    do
        if [[ $1 =~ ^- ]];
        then
            LNOPTS+=($1)
        else
            ARGS+=($1)
        fi
        shift
    done

    if (( ${#ARGS[*]} < 2 ));
    then
        error "not enough arguments"
        usage
        exit 1
    fi

    DEST="${ARGS[-1]}"
    unset ARGS[$(( ${#ARGS[*]} - 1))]

    if (( ${#ARGS[*]} > 1 )) && ! [[ -d "$DEST" ]];
    then
        error "DEST must be a directory if multiple DBs are given" >&2
        exit 1
    fi
}


function link_db()
{
    local DB="$1"
    local DIR="$(dirname "$DB")"
    local BASENAME="$(basename "$DB")"
    local EXT=".${BASENAME##*.}"

    if [[ -f "$DB" && ("$EXT" == ".db" || "$EXT" == ".dam") ]];
    then
        BASENAME="${BASENAME%$EXT}"
    elif [[ -f "$DB.db" ]];
    then
        EXT=".db"
    elif [[ -f "$DB.dam" ]];
    then
        EXT=".dam"
    else
        echo "DBln: error: invalid DB file: $DB" >&2
        exit 1
    fi

    if [[ -d "$DEST" ]];
    then
        ln "${LNOPTS[@]}" "$DIR/$BASENAME$EXT" "$DIR/.$BASENAME."* "$DEST"
    else
        local DESTDIR="$(dirname "$DEST")"
        local DESTBASENAME="$(basename "${DEST%$EXT}")"

        ln "$LNOPTS" "$DIR/$BASENAME$EXT" "$DESTDIR/$DESTBASENAME$EXT"

        for FILE in "$DIR/.$BASENAME."*;
        do
            local POSTFIX="$(basename "$FILE")"
            POSTFIX="${POSTFIX#.$BASENAME}"

            ln "$LNOPTS" "$FILE" "$DESTDIR/.$DESTBASENAME$POSTFIX"
        done
    fi
}


function main()
{
    parse_args "$@"

    for DB in ${ARGS[*]};
    do
        link_db "$DB"
    done
}


main "$@"
