#!/bin/bash

# - - - - - - - - - - - - - - - - - - - - - - - - - - - #
#   EO/CDR-group layers GeoServer<-->GeoNode sync
#
# The script sync the layers between the EDP GeoNode instance
# and its underlying GeoServer installation, with regards
# to the EO_CDR workspace.
#
# @see https://docs.geonode.org/en/master/admin/mgmt_commands/index.html
#
# @author pcampalani
# - - - - - - - - - - - - - - - - - - - - - - - - - - - #

# NOTE: groups are currently recognized by GeoNode only as
#       all lower-case names (despite they might have upper-case
#       letters in their original name.
#       This script automatically turns group names to lower-case
#       in the CLI calls (see ${VAR,,}), so the user can specify
#       groups by their correct name in the permissions file.

# TODO: -w WORKSPACE [-s STORE [STORE ...]] --filter "regex_layer_name"

#
# variables
#

PYTHON='/home/geonode/.virtualenvs/geonode/bin/python'
PYTHONPATH='/opt/geonode' # TODO ignored by python
MANAGE_PY="${PYTHONPATH}/manage.py"
DJANGO_SETTINGS_MODULE='geonode.local_settings'

OWNER='pcampalani'
PERMS_FOLDER="/home/pcampalani/geonode/perms"

PERMS_DEFAULTS_U='users.default'
PERMS_DEFAULTS_G='groups.default'
PERMS_FILE_EXT='perms'
PERMS_FILE_KEY_U='U:'
PERMS_FILE_KEY_G='G:'

# style
underline=`tput smul`
nounderline=`tput rmul`
bold=`tput bold`
normal=`tput sgr0`

# logging
alias log='echo ${bold}[$ME]${normal} '
alias logn='echo -n ${bold}[$ME]${normal} '
shopt -s expand_aliases

# args
ME="$( basename $0 )"
WORKSPACE_ARGS=('--workspace' '-w')
STORE_ARGS=('--store' '-s')
FILTER_ARGS=('--filter' '-f')
SYNC_ARGS=('--sync-layers' '-sl')
DRYRUN_ARGS=( '--dry-run' '-n' )
HELP_ARGS=( '--help' '-h' )
MIN_ARGS=2 # (help excluded)
MAX_ARGS=8 #   ''     ''
USAGE="\

  ${bold}$ME${normal} ${WORKSPACE_ARGS[0]} ${underline}WORKSPACE${normal} [${underline}OPTION${normal}]
  
  ${bold}[${WORKSPACE_ARGS[0]}, ${WORKSPACE_ARGS[1]}] WORKSPACE${normal}
      Only consider layers in the specified GeoServer workspace.

  OPTIONS:

  ${bold}[${STORE_ARGS[0]}, ${STORE_ARGS[1]}] STORE${normal}
      Only consider layers in the specified GeoServer store.
  
  ${bold}[${FILTER_ARGS[0]}, ${FILTER_ARGS[1]}] FILTER${normal}
      Only consider layers whose name matches the given filter (regex: "*FILTER*")
  
  ${bold}[${SYNC_ARGS[0]}, ${SYNC_ARGS[1]}]${normal}
      Synchronize the list of layers from GeoServer to GeoNode before updating the permissions.
      Existing layers that are deleted from GeoServer will be deleted from the GeoNode catalog,
      and new GeoServer layers will be added to GeoNode.
  
  ${bold}[${DRYRUN_ARGS[0]}, ${DRYRUN_ARGS[1]}]${normal}
      Dry-run test: prints out commands to console without executing them.

  ${bold}[${HELP_ARGS[0]}, ${HELP_ARGS[1]}]${normal}
      Prints this text.
"

# store script dir
PWD="$( pwd )"
SOURCE="${BASH_SOURCE[0]}"
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
cd -P "$PWD" # back to original folder

# exit codes:
CODE_OK=0
CODE_WRONG_USAGE=1


#
#check args
#

if [ $# -lt $MIN_ARGS -o $# -gt $MAX_ARGS ]; then
   echo "$USAGE"
   exit $CODE_WRONG_USAGE
fi

# parse args
while [ $# -gt 0 ]; do
   case "$1" in
      ${WORKSPACE_ARGS[0]}|${WORKSPACE_ARGS[1]}) WORKSPACE="$2"; shift;;
      ${STORE_ARGS[0]}|${STORE_ARGS[1]}) STORE="$2"; shift;;
      ${FILTER_ARGS[0]}|${FILTER_ARGS[1]}) FILTER="$2"; shift;;
      ${SYNC_ARGS[0]}|${SYNC_ARGS[1]}) SYNC="$2"; shift;;
      ${HELP_ARGS[0]}|${HELP_ARGS[1]})  echo "$USAGE"; exit $CODE_OK ;;
      ${DRYRUN_ARGS[0]}|${DRYRUN_ARGS[1]})  DRY="echo ";;
      *) echo -e "(!) Unknown argument \"$1\".\n$USAGE";
         exit $CODE_WRONG_USAGE;;
   esac
   shift
done

# missing both workspace and store
if [ -z ${WORKSPACE+x} ]
then
   echo "WORKSPACE argument missing."
   echo "$USAGE"
   exit $CODE_WRONG_USAGE
fi

#
# run
#

[ ! -z "$STORE" ] && store_param="--store $STORE"
[ ! -z "$FILTER" ] && filter_param="--filter $FILTER"

# register new layers from GeoServer to GeoNode
if [ ! -z "${SYNC+x}" ]
then
   log "Syncing GeoNode layers from GeoServer."
   $DRY "$PYTHON" "$MANAGE_PY" updatelayers \
       --settings $DJANGO_SETTINGS_MODULE \
       --workspace $WORKSPACE \
       $store_param \
       $filter_param \
       --user $OWNER \
       --remove-deleted \
       --skip-geonode-registered
fi

# 
# set the permissions defined in the permissions tree
#
workspace_root="${PERMS_FOLDER}/${WORKSPACE}"

unset stores
declare -a stores

# if store was not specified, fetch all available stores
if [ ! -z "$STORE" ]
then
   stores+=("$STORE")
else
   while IFS= read -d '' -r store_path
   do
      stores+=("$( basename "$store_path" )")
   done < <(find "$workspace_root" -maxdepth 1 -mindepth 1 -type d -print0)
fi

for store in "${stores[@]}"
do
   store_root="${workspace_root}/${store}"

   find "$store_root" -maxdepth 1 -mindepth 1 -type d -print0 \
   | while IFS= read -d '' -r perms_path
   do
      # extract data from path
      usr_default="${perms_path}/$PERMS_DEFAULTS_U"
      grp_default="${perms_path}/$PERMS_DEFAULTS_G"
      perm=$( basename "$perms_path" )

      unset def_perms_layers
      declare -a def_perms_layers

      while IFS= read -d '' -r layer_perms_path
      do
         layer_name="$( basename "${layer_perms_path%.$PERMS_FILE_EXT}" )"

         # skip layers not matching the filter
         if [ ! -z "${FILTER+x}" ]
         then
            if [[ $layer_name != *$FILTER* ]]
            then
               log "Skipping layer \"$layer_name\"."
               continue
            fi
         fi

         # read u/g permissions
         if [ ! -s "$layer_perms_path" ]
         then
            # file is empty: add to default list for bulk perms settings
            def_perms_layers+=("$layer_name")
         else
            # layer specific perms
            usrs="$( cat "$layer_perms_path" | sed -E -n "s/$PERMS_FILE_KEY_U(.*)/\1/p" | tr ',' ' ' )"
            grps="$( cat "$layer_perms_path" | sed -E -n "s/$PERMS_FILE_KEY_G(.*)/\1/p" | tr ',' ' ' )"

            [ ! -z "$usrs" ] && usrs_params="--users $usrs"
            [ ! -z "$grps" ] && grps_params="--groups $grps"

            log "Setting $perm permissions (U: $usrs | G: $grps) on layer $layer_name"
            $DRY "$PYTHON" "$MANAGE_PY" set_layers_permissions \
               --settings $DJANGO_SETTINGS_MODULE \
               $usrs_params ${grps_params,,} \
               --permission $perm \
               --resources $layer_name
         fi
      done < <(find "$perms_path" -mindepth 1 -type f -name "*.$PERMS_FILE_EXT" -print0)
      # NOTE: pipeline creates subshells, so def_perms_layers variable is not seen

      if [ ${#def_perms_layers[@]} -gt 0 ]
      then
         unset usrs usrs_params
         unset grps grps_params

         # set default perms on remaining layers
         [ -f "$usr_default" ] && usrs="$( cat "$usr_default" | tr ',' ' ' )"
         [ -f "$grp_default" ] && grps="$( cat "$grp_default" | tr ',' ' ' )"

         [ ! -z "$usrs" ] && usrs_params="--users $usrs"
         [ ! -z "$grps" ] && grps_params="--groups $grps"

         log "Setting default $perm permissions (U: $usrs | G: $grps) on layers: ${def_perms_layers[@]}"
         $DRY "$PYTHON" "$MANAGE_PY" set_layers_permissions \
            --settings $DJANGO_SETTINGS_MODULE \
            $usrs_params ${grps_params,,} \
            --permission $perm \
            --resources ${def_perms_layers[@]}
      fi
   done
done

exit $CODE_OK
