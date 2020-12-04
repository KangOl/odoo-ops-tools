#!/usr/bin/env bash
set -eu
set -o pipefail
if [[ "${DEBUG:-}" = "1" ]]; then
    set -x
fi
PORT=7969
: "${DB:=test}"
ROOT=~/devel/odoo
FS=~/Library/Application\ Support/Odoo/filestore
GR=$(git rev-parse --show-toplevel)
pushd "${GR}" >/dev/null
AD=
LOGLEVEL=ERROR
LOGFILE=
KEEP=N
TEST_ENABLED="--test-enable"
BR=$(git symbolic-ref --short HEAD || echo "?")
RUN=N
IGNORED_MODULES="l10n_|hw_|test_module|theme_|auth_ldap|pos_blackbox_be"
ALLMODS=$(fd '__openerp|manifest__.py' . -e py -x basename '{//}' | grep -vE "$IGNORED_MODULES" | tr '\n' ,)
ALLALLMODS=$(fd '__openerp|manifest__.py' . -e py -x basename '{//}'| tr '\n' ,)

opt=
while getopts 'hnNkKrseEtTwvl:' opt; do
  case "$opt" in
    h)
      echo "Usage:"
      echo "  $0 (-h | --help)"
      echo "  $0 [-k [-n | -N]] [-e | -E] [-w | -v] [-r | -s] [-l <logfile>] [<MODS> [<ODOO_OPTIONS>...]]"
      echo ""
      echo "Options:"
      echo "  -n, -N  do not execute test. Only install module (without demo data if -N). aka dry-run."
      echo "  -k      keep existing \`test\` database"
      echo "  -e, -E  include Enterprise in addon-path (trust branches if -E)"
      echo "  -t, -T  include Themes in addon-path (trust branches if -T)"
      echo "  -w      log all warnings"
      echo "  -v      log info"
      echo "  -r      run odoo after db creation"
      echo "  -s      run odoo shell after db creation"
      echo "  -l <logfile>"
      exit 0
      ;;
    n)
        TEST_ENABLED=
      ;;
    N)
        TEST_ENABLED="--without-demo=1"
      ;;
    k)
        KEEP=u
      ;;
    K)
        KEEP=i
      ;;
    r)
        RUN=Y
      ;;
    s)
        RUN=S
      ;;
    e | E)
        pushd "${ROOT}/enterprise" >/dev/null
        if [[ "$opt" == "e" ]]; then
            EBR=$(git symbolic-ref --short HEAD)
            if [[ "$EBR" != "$BR" ]]; then
                echo "Enterprise branch ($EBR) is different that current one ($BR)" >&2
                exit 1
            fi
        fi
        AD=${AD}${PWD},
        ALLMODS=${ALLMODS},$(fd '__openerp|manifest__.py' . -e py -x basename '{//}' | grep -vE "$IGNORED_MODULES" | tr '\n' ,)
        ALLALLMODS=${ALLALLMODS},$(fd '__openerp|manifest__.py' . -e py -x basename '{//}'| tr '\n' ,)
        popd >/dev/null
      ;;
    t | T)
        pushd "${ROOT}/themes" >/dev/null
        if [[ "$opt" == "t" ]]; then
            TBR=$(git symbolic-ref --short HEAD)
            if [[ "$TBR" != "$BR" ]]; then
                echo "Themes branch ($TBR) is different that current one ($BR)" >&2
                exit 1
            fi
        fi
        AD=${AD}${PWD},
        ALLALLMODS=${ALLALLMODS},$(fd '__openerp|manifest__.py' . -e py -x basename '{//}'| tr '\n' ,)
        popd >/dev/null
      ;;
    w)
       LOGLEVEL=WARN
      ;;
    v)
       LOGLEVEL=INFO
      ;;
    l)
       LOGFILE="$OPTARG"
       ;;
    ?) exit 1
     ;;
   *);;
  esac
done

shift $((OPTIND - 1))

MODS="${1:-base}"
if [[ "$MODS" == "all" ]]; then
    MODS=$ALLMODS
elif [[ "$MODS" == "test" ]]; then
    MODS=$(echo -n "$ALLMODS" | tr ' ,' '\n' | grep -E '^test_' | tr '\n' ,)
else
    # validate MODS agains $ALLALLMODS
    UNK=$(echo "$ALLALLMODS" "$ALLALLMODS" "$MODS" | tr ' ,' '\n' | sort | uniq -u | tr '\n' ' ')
    if [[ -n "$UNK" ]]; then
        echo "Unknow modules: $UNK" >&2
        exit 1
    fi
fi
shift || true


D=odoo
if [[ -f openerp/__init__.py ]]; then
    D=openerp
fi

B=odoo-bin
if [[ -f openerp-server ]]; then
    B=openerp-server
fi

LOGHANDLERS="
    --log-handler=:${LOGLEVEL} \
    --log-handler=${D}.modules.loading:WARN --log-handler=${D}.modules.graph:CRITICAL \
    --log-handler=${D}.modules.module:INFO --log-handler=${D}.modules.registry:INFO \
    --log-handler=${D}.tests.common:INFO \
"

if [[ "$KEEP" == "N" ]]; then
    IU="-i"
    set -x
    dropdb --if-exists "$DB"
    rm -rf "${FS:?}/${DB}"
    createdb "$DB"
    { set +x; } 2>/dev/null

    _L10N=$(echo -n "$MODS" | awk -vRS=, -vFS=_ '/^l10n_/{print $2}' | sort | uniq | tr '\n' ' ')
    declare -a L10N=($_L10N)
    if test "${#L10N[@]}" -gt 0; then
        set -x
        ./$B --addons-path="${AD}./addons" \
            --db-filter="^${DB}\$" --pidfile=/tmp/odoo.pid --stop-after-init \
            --xmlrpc-port=${PORT} \
            ${LOGHANDLERS} \
            --logfile="${LOGFILE}" -i base -d "$DB"
        psql -d "$DB" -c "UPDATE res_partner SET country_id = (SELECT id FROM res_country WHERE lower(code)='${L10N[0]}')"

        { set +x; } 2>/dev/null
        unset L10N[0]
        set -x
    fi
else
    IU="-$KEEP"     # yuck
    # TODO determine $IU automatically depending of module(s) state
    set -x
fi

./$B --addons-path="${AD}./addons" \
    --db-filter="^${DB}\$" --pidfile=/tmp/odoo.pid --stop-after-init \
    ${TEST_ENABLED} \
    --xmlrpc-port=${PORT} \
    ${LOGHANDLERS} \
    --logfile="${LOGFILE}" $IU "${MODS}" -d "$DB" "$@"

if [[ "$RUN" != "N" ]]; then
    COMMAND=
    if [[ "$RUN" == "S" ]]; then COMMAND=shell; fi;
    ./$B --addons-path="${AD}./addons" $COMMAND \
        --db-filter="^${DB}\$" --pidfile=/tmp/odoo.pid \
        --logfile="${LOGFILE}" -d "$DB" "$@"
fi
