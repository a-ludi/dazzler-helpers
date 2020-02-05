#!/bin/bash

# Unofficial Bash Strict Mode (http://redsymbol.net/articles/unofficial-bash-strict-mode/)
set -euo pipefail
IFS=$'\n'

PROG="$0"


function error()
{
    echo "$PROG: error: $@"
} >&2


function usage()
{
    echo "usage: $PROG DB BAM..."
} >&2


function print_help()
{
    usage
    echo
    echo 'Create DB from the sequences in contained each BAM. This is intended for'
    echo 'read data produced by the PacBIO RS II'
    echo
    echo 'Arguments:'
    echo '  DB   Destination database.'
    echo '  BAM  Source files for sequences. Takes any file format'
    echo '       supported by `samtools`.'
} >&2


function parse_args()
{
    if (( $# < 1 ));
    then
        error "DB missing"
        usage
        exit 1
    elif [[ "$1" == "-h" ]];
    then
        print_help
        exit 1
    elif (( $# < 2 ));
    then
        error "at least one BAM must be supplied"
        usage
        exit 1
    fi

    DB="$1"
    shift
    SOURCES=( $* )
}


function add_source_to_db()
{
    local SOURCE="$1"

    echo -n "Processing $SOURCE ... " >&2
    samtools view "$SOURCE" | \
        awk -F'\t' '
            function optfield(id, type) {
                for (i = 12; i <= NF; ++i)
                    if (id == substr($i, 1, 2) && substr($i, 4, 1) == type)
                        return substr($i, 6);
            }
            { printf ">%s RQ=%s\n%s\n", $1, optfield("rq", "f"), $10 }
        ' | \
        fold -w9999 | \
        fasta2DB -i "$DB"
    echo "done" >&2
}


function main()
{
    parse_args "$@"

    for SOURCE in ${SOURCES[*]};
    do
        add_source_to_db "$SOURCE"
    done
}


main "$@"
