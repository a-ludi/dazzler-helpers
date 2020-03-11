#!/bin/bash

# Unofficial Bash Strict Mode (http://redsymbol.net/articles/unofficial-bash-strict-mode/)
set -euo pipefail
IFS=$'\n\t'
PROG="$(basename "$0")"


function set_defaults()
{
    declare -a SBATCH_ARGS
    NUM_THREADS=4
    MAX_MEMGB=0
}


function error()
{
    if (( $# > 0 ));
    then
        echo "$PROG: error:" "$@"
    else
        echo
    fi
} >&2


function bail_out()
{
    error "$@"
    exit 1
}


function bail_out_usage()
{
    error "$@"
    error
    print_usage
    exit 1
}


function log()
{
    echo "--" "$@"
} >&2


function print_usage()
{
    echo "USAGE:  $PROG [-h] [--dry-run] [--sbatch=<arg> ...] [--blocks=<block-ids>] [<damapper-flags>] <reference:dam> <reads:db> ..."
} >&2


function print_help()
{
    print_usage
    echo
    echo 'Run damapper on every block of <reads:db> using `sbatch`.'
    echo
    echo 'Positional arguments:'
    echo ' <reference:dam>  Reference'
    echo ' <reads:db>       Reads/queries. Note: this script accepts exactly one DB.'
    echo
    echo 'Optional arguments:'
    echo ' <damapper-flags> All damapper flags are accepted. The parameters -T and -M are'
    echo '                  automatically translated to `sbatch` parameters.'
    echo ' --sbatch=<args>  Pass <args> to call to `sbatch`.'
    echo ' --blocks=<block-ids>  Align only blocks <block-ids>.'
    echo ' --help, -h       Prints this help.'
    echo ' --usage          Print a short command summary.'
    echo ' --version        Print software version.'
    echo
    echo 'Envorinment variables:'
    echo ' BLOCK_IDS        Pass a list of blocks to align. Takes the same format as'
    echo '                  `sbatch --array`'
    echo '                  automatically translated to `sbatch` parameters.'
    echo ' --dry-run, -n    Print the sbatch script to stdout and do nothing else.'
    echo ' --sbatch=<arg>   Pass <arg> to `sbatch`; repeat for multiple args.'
    echo ' --help, -h       Prints this help.'
    echo ' --usage          Print a short command summary.'
    echo ' --version        Print software version.'
} >&2


function print_version()
{
    echo "$PROG v0"
    echo
    echo "Copyright © 2019, Arne Ludwig <arne.ludwig@posteo.de>"
} >&2


declare -a DAMAPPER_ARGS


function parse_args()
{
    ARGS=()
    for ARG in "$@";
    do
        if [[ "${ARG:0:1}" == - ]];
        then
            case "$ARG" in
                --dry-run|-n)
                    DRYRUN=1
                    ;;
                --sbatch=*)
                    SBATCH_ARGS+=( "${ARG#--sbatch=}" )
                    ;;
                --blocks=*)
                    BLOCK_IDS="${ARG#--blocks=}"
                    ;;
                -h|--help)
                    print_help

                    exit
                    ;;
                --usage)
                    print_usage

                    exit
                    ;;
                --version)
                    print_version

                    exit
                    ;;
                -T*)
                    NUM_THREADS=$(( ${ARG#-T} ))
                    DAMAPPER_ARGS+=("$ARG")
                    ;;
                -M*)
                    MAX_MEMGB=$(( ${ARG#-M} ))
                    DAMAPPER_ARGS+=("$ARG")
                    ;;
                -[vbpzCN]|-[vbpzCN][vbpzCN]|-[vbpzCN][vbpzCN][vbpzCN]|-[vbpzCN][vbpzCN][vbpzCN][vbpzCN]|-[vbpzCN][vbpzCN][vbpzCN][vbpzCN][vbpzCN]|-[vbpzCN][vbpzCN][vbpzCN][vbpzCN][vbpzCN][vbpzCN]|-k*|-t*|-P*|-e*|-s*|-n*|-m*)
                    DAMAPPER_ARGS+=("$ARG")
                    ;;
            esac
        else
            ARGS+=( "$ARG" )
        fi
    done

    (( ${#ARGS[*]} >= 1 )) || bail_out_usage "<reference:dam> is missing"
    REFERENCE="${ARGS[0]}"

    (( ${#ARGS[*]} >= 2 )) || bail_out_usage "<reads:db> is/are missing"
    READS="${ARGS[1]}"
    if [[ "$READS" =~ \.(dam|db) ]];
    then
        READS_TYPE="${READS##*.}"
        READS="${READS%.*}"
    else
        if [[ -e "$READS.db" ]];
        then
            READS_TYPE="db"
        elif [[ -e "$READS.dam" ]];
        then
            READS_TYPE="dam"
        else
            bail_out "cannot infer type of <reads:db>"
        fi
    fi
    READS_FILE="$READS.$READS_TYPE"

    (( ${#ARGS[*]} == 2 )) || bail_out_usage "too many arguments"
}


function get_num_blocks()
{
    awk '
        ($1 == "blocks") {
            print $3;
            exit;
        }
    ' "$1"
}


function build_damapper_script()
{
    echo '#!/bin/bash'
    echo "#SBATCH --array=${BLOCK_IDS:-1-$NUM_READS_BLOCKS}"
    echo "#SBATCH --cpus-per-task=$NUM_THREADS"
    (( MAX_MEMGB == 0 )) || echo "#SBATCH --mem=${MAX_MEMGB}G"
    for ARG in "${SBATCH_ARGS[@]}"
    do
        echo "#SBATCH $ARG"
    done
    echo
    echo 'damapper' "${DAMAPPER_ARGS:+${DAMAPPER_ARGS[@]}}" "$REFERENCE" "$READS.\$SLURM_ARRAY_TASK_ID.$READS_TYPE"
}


function write_damapper_script()
{
    DAMAPPER_SCRIPT="$(mktemp --tmpdir "damapper.slurm-XXXXXX.sh")"
    # clean up on script end
    trap 'rm -f "$DAMAPPER_SCRIPT"' EXIT

    if (( ${DRYRUN:-0} == 0 ));
    then
        build_damapper_script > "$DAMAPPER_SCRIPT"
    else
        build_damapper_script
    fi
}


function dispatch_jobs()
{
    sbatch "$DAMAPPER_SCRIPT"
}


function main()
{
    set_defaults
    parse_args "$@"

    NUM_READS_BLOCKS=$(( $(get_num_blocks "$READS_FILE") ))
    write_damapper_script

    if (( ${DRYRUN:-0} == 0 ));
    then
        dispatch_jobs
    fi
}


main "$@"
