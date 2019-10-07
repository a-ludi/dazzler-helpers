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
    echo "USAGE:  $PROG GENBANK_LINK DAM"
} >&2


function print_help()
{
    usage
    echo
    echo 'Create DAM from the assembly pointed to by GENBANK_LINK storing the accession'
    echo 'in the DB header file. `DAM2fasta` will write to `ACCESSION.fasta`.'
    echo
    echo 'Arguments:'
    echo '  GENBANK_LINK  Link to a GenBank assembly in (gzipped) FASTA format.'
    echo '  DAM           Destination database.'
} >&2


function parse_args()
{
    if (( $# < 1 ));
    then
        error "GENBANK_LINK missing"
        usage
        exit 1
    elif [[ "$1" == "-h" ]];
    then
        print_help
        exit 1
    elif (( $# < 2 ));
    then
        error "DAM missing"
        usage
        exit 1
    elif (( $# > 2 ));
    then
        error "too many arguments"
        usage
        exit 1
    fi

    GENBANK_LINK="$1"
    DAM="$2"

    ACCESSION="$(echo "$1" | sed -E 's!.*/(GCA_[0-9]+\.[0-9]+)_[^/]+!\1!')";

    if [[ -z $ACCESSION ]]; then
        error "illegal GenBank link: file name must start with GCA_[0-9]+"

        exit 1
    fi
}


function create_db()
{
    curl "$GENBANK_LINK" | \
        zcat -f | \
        { fold; echo; } | \
        fasta2DAM -i$ACCESSION "$DAM"
}


function main()
{
    parse_args "$@"
    create_db
}


main "$@"
