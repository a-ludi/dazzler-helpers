#!/bin/bash

# Unofficial Bash Strict Mode (http://redsymbol.net/articles/unofficial-bash-strict-mode/)
set -euo pipefail
IFS=$'\n\t'
PROG="$(basename "$0")"


function set_defaults()
{
    declare -a SBATCH_ARGS
    declare -a DB_STUBS
    declare -a DB_TYPES
    declare -a DB_FILES
    declare -a DB_BLOCKS
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
    echo "USAGE:  $PROG [-h] [--dry-run] [--print-plan] [--sbatch=<arg> ...] [<daligner-flags>] <subject:db|dam>[@<id-spec>] [<target:db|dam>[@<id-spec>] ...]"
} >&2


function print_help()
{
    print_usage
    echo
    echo 'Run daligner on every combination of blocks using `sbatch`.'
    echo
    echo 'Positional arguments:'
    echo ' <subject:db|dam> DB with A-reads'
    echo ' <target:db|dam>  DB(s) with B-reads. Uses <subject> and `-I` if ommitted.'
    echo
    echo 'Optional arguments:'
    echo ' <daligner-flags> All daligner flags are accepted. The parameters -T and -M are'
    echo '                  automatically translated to `sbatch` parameters.'
    echo ' --dry-run, -n    Print the sbatch script to stdout and exit.'
    echo ' --print-plan, -p Print execution plan and exit.'
    echo ' --sbatch=<args>  Pass <args> to call to `sbatch`.'
    echo ' --help, -h       Prints this help.'
    echo ' --usage          Print a short command summary.'
    echo ' --version        Print software version.'
    echo ' --version        Print software version.'
    echo
    echo '@-syntax definition:'
    echo ' <id-spec>      ::== <id-spec-item>[,<id-spec-item> ...]'
    echo ' <id-spec-item> ::== <id>|<id-range>'
    echo ' <id-range>     ::== <id>-<id>'
    echo ' <id>           ::== <non-zero-digit>[<digit> ...]'
} >&2


function print_version()
{
    echo "$PROG v0"
    echo
    echo "Copyright © 2019, Arne Ludwig <arne.ludwig@posteo.de>"
} >&2


declare -a DALIGNER_ARGS


function parse_args()
{
    ARGS=()
    for ARG in "$@";
    do
        if [[ "${ARG:0:1}" == - ]];
        then
            case "$ARG" in
                --dry-run|-n)
                    DRY_RUN=1
                    ;;
                --print-plan)
                    PRINT_PLAN=1
                    ;;
                --sbatch=*)
                    SBATCH_ARGS+=( "${ARG#--sbatch=}" )
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
                    DALIGNER_ARGS+=("$ARG")
                    ;;
                -M*)
                    MAX_MEMGB=$(( ${ARG#-M} ))
                    DALIGNER_ARGS+=("$ARG")
                    ;;
                -[vabBAI]|-[vabBAI][vabBAI]|-[vabBAI][vabBAI][vabBAI]|-[vabBAI][vabBAI][vabBAI][vabBAI]|-[vabBAI][vabBAI][vabBAI][vabBAI][vabBAI]|-[vabBAI][vabBAI][vabBAI][vabBAI][vabBAI][vabBAI]|-[vabBAI][vabBAI][vabBAI][vabBAI][vabBAI][vabBAI][vabBAI]|-k*|-%*|-w*|-h*|-t*|-P*|-e*|-l*|-s*|-H*|-m*)
                    DALIGNER_ARGS+=("$ARG")
                    ;;
            esac
        else
            ARGS+=( "$ARG" )
        fi
    done

    (( ${#ARGS[*]} >= 1 )) || bail_out_usage "<subject> is missing"

    parse_db_args "${ARGS[@]}"
}


function parse_db_args()
{
    local I
    for (( I = 0; I < $#; ++I ))
    do
        local II=$(( I + 1 ))
        local DB="${!II}"
        if [[ "$DB" =~ @ ]]
        then
            parse_db_blocks "${DB##*@}" > /dev/null || bail_out "invalid @-syntax: $DB"
            DB_BLOCKS[$I]="${DB##*@}"
            DB="${DB%@*}"
        fi

        if [[ "$DB" =~ \.(dam|db)$ ]];
        then
            DB_TYPES[$I]="${DB##*.}"
            DB_STUBS[$I]="${DB%.*}"
        else
            if [[ -e "$DB.db" ]];
            then
                DB_TYPES[$I]="db"
            elif [[ -e "$DB.dam" ]];
            then
                DB_TYPES[$I]="dam"
            else
                bail_out "cannot infer type of DB: $DB"
            fi
        fi

        DB_FILES[$I]="${DB_STUBS[$I]}.${DB_TYPES[$I]}"
    done

    NUM_DBS="${#DB_FILES[*]}"
}


function dry_run()
{
    [[ -v DRY_RUN ]]
}


function should_print_plan()
{
    [[ -v PRINT_PLAN ]]
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


function prepare_block_ids()
{
    NUM_JOBS=1
    local I
    for (( I = 0; I < NUM_DBS; ++I ))
    do
        local DB="${DB_FILES[$I]}"
        local NUM_BLOCKS=$(( $(get_num_blocks "$DB") ))
        local BLOCKS="${DB_BLOCKS[$I]:-}"

        if [[ -n "$BLOCKS" ]]
        then
            parse_db_blocks "$BLOCKS" | while read -r BLOCK_ID
            do
                (( 1 <= BLOCK_ID && BLOCK_ID <= NUM_BLOCKS )) || \
                    bail_out "invalid blocks-spec '$BLOCKS': $BLOCK_ID out of bounds"
            done

            (( NUM_JOBS *= $(parse_db_blocks "$BLOCKS" | wc -l) ))
        else
            DB_BLOCKS[$I]="1-$NUM_BLOCKS"
            (( NUM_JOBS *= NUM_BLOCKS ))
        fi
    done

    if (( NUM_DBS == 1 ))
    then
        NUM_JOBS=$(( (NUM_JOBS * (NUM_JOBS + 1)) / 2 ))
    fi
}


function parse_db_blocks()
{
    while IFS='-' read -rd',' FROM TO
    do
        if [[ -n "${TO:-}" ]]
        then
            (( FROM <= TO )) || bail_out "invalid blocks-spec '$FROM-$TO': <to> must be greater than or equal to <from>"

            local I
            for (( I = FROM; I <= TO; ++I ))
            do
                echo "$I"
            done
        else
            echo "$FROM"
        fi
    done <<<"$1,"
}


function build_db_args_script()
{
    cat <<-'EOF'
		JOB_IDX=$(( SLURM_ARRAY_TASK_ID - 1 ))
		if (( NUM_DBS == 1 ))
		then
		    BLOCKS=( $(parse_db_blocks "${DB_BLOCKS[0]}") )

		    A_IDX=0
		    B_IDX=0
		    for (( I = 0; I < JOB_IDX; ++I ))
		    do
		        if (( B_IDX + 1 < ${#BLOCKS[*]} ))
		        then
		            (( ++B_IDX ))
		        else
		            (( ++A_IDX ))
		            B_IDX="$A_IDX"
		        fi
		    done

		    DB_ARGS=(
		        "-I"
		        "${DB_STUBS[0]}.${BLOCKS[A_IDX]}"
		        "${DB_STUBS[0]}.${BLOCKS[B_IDX]}"
		    )
		else
		    for (( I = NUM_DBS - 1; I >= 0; --I ))
		    do
		        BLOCKS=( $(parse_db_blocks "${DB_BLOCKS[$I]}") )
		        BLOCK_IDX=$(( JOB_IDX % ${#BLOCKS[*]} ))
		        JOB_IDX=$(( JOB_IDX / ${#BLOCKS[*]} ))
		        DB_ARGS[$I]="${DB_STUBS[$I]}.${BLOCKS[$BLOCK_IDX]}"
		    done
		fi
EOF
}


function build_damapper_script()
{
    echo '#!/bin/bash'
    echo "#SBATCH --array=1-$NUM_JOBS"
    echo "#SBATCH --cpus-per-task=$NUM_THREADS"
    (( MAX_MEMGB == 0 )) || echo "#SBATCH --mem=${MAX_MEMGB}G"
    if (( ${#SBATCH_ARGS[*]} > 0 ))
    then
        for ARG in "${SBATCH_ARGS[@]}"
        do
            echo "#SBATCH $ARG"
        done
    fi
    echo "NUM_DBS='$NUM_DBS'"
    echo 'DB_STUBS=('
    for DB_STUB in "${DB_STUBS[@]}"
    do
        echo "    $DB_STUB"
    done
    echo ')'
    echo 'DB_BLOCKS=('
    for DB_BLOCK in "${DB_BLOCKS[@]}"
    do
        echo "    $DB_BLOCK"
    done
    echo ')'
    echo
    build_db_args_script
    echo
    echo "daligner" "${DALIGNER_ARGS:+${DALIGNER_ARGS[@]}}" '"${DB_ARGS[@]}"'
}


function print_plan()
{
    # set -x
    for (( SLURM_ARRAY_TASK_ID = 1; SLURM_ARRAY_TASK_ID <= NUM_JOBS; ++SLURM_ARRAY_TASK_ID ))
    do
        eval "$(build_db_args_script)"

        ! dry_run || echo -n '# '
        echo "JOB_ID=$SLURM_ARRAY_TASK_ID daligner" "${DALIGNER_ARGS:+${DALIGNER_ARGS[@]}}" \
                "${DB_ARGS[@]}"
    done
    # set +x
}


function write_damapper_script()
{
    DALIGNER_SCRIPT="$(mktemp --tmpdir "daligner.slurm-XXXXXX.sh")"
    # clean up on script end
    trap 'rm -f "$DALIGNER_SCRIPT"' EXIT

    if dry_run
    then
        build_damapper_script
    else
        build_damapper_script > "$DALIGNER_SCRIPT"
    fi
}


function dispatch_jobs()
{
    sbatch "$DALIGNER_SCRIPT"
}


function main()
{
    set_defaults
    parse_args "$@"

    prepare_block_ids
    write_damapper_script

    if should_print_plan
    then
        print_plan
    elif ! dry_run
    then
        export -f parse_db_blocks
        dispatch_jobs
    fi
}


main "$@"
