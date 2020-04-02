#!/bin/sh

create=( "stack_check" "stack_cleanup" "network_cleanup" "stack_deploy" "stack_deploy_check" )
create_web=( "stack_check" "stack_cleanup" "network_cleanup" "stack_deploy" "stack_deploy_check" "stack_web_deploy_check" )
destroy=( "stack_check" "stack_cleanup" "network_cleanup" )

function service_overlord() {
  local step_number=0 timeout_power=2 timeout_power_limit=7 timeout_value=2
  local current_step="" ERROR=""
  export DOCKER_HOST=$docker_host
  export DNS_SUFFIX=$dns_suffix
  url="http://${stack}.${DNS_SUFFIX}"
  while [ "$step_number" -lt "${#steps[@]}" ] && [ "$timeout_power" -lt "$timeout_power_limit" ]
  do
    if [[ "$current_step" == ${steps[$step_number]} ]]
    then
      sleep $((timeout_value ** $timeout_power))
    else
      current_step=${steps[$step_number]}
      printf "${current_step}...."
    fi
    case $current_step in
      "stack_check")
        docker stack ps $stack > /dev/null 2>&1
        [[ $? -ne 0 ]] && step_number=$((step_number+3)) && echo "Done" && continue
        success step_number
        ;;
      "stack_cleanup")
        docker stack rm $stack > /dev/null 2>&1
        [[ $? -ne 0 ]] && error $current_step
        success step_number
        ;;
      "network_cleanup")
        docker network ls | grep "${stack}_default" > /dev/null 2>&1
        [[ $? -eq 0 ]] && timeout timeout_power && continue
        success step_number
        ;;
      "stack_deploy")
        { ERROR=$( { docker stack deploy -c docker-compose.yml $stack ; } 2>&1 ); } 3>&1
        [[ $? -ne 0 ]] && error "$ERROR"
        success step_number
        ;;
      "stack_deploy_check")
        service_state=`docker service ps ${stack}_${service} | awk 'FNR == 2 {print $6}'`
        [[ $service_state != "Running" ]] && timeout timeout_power && continue
        success step_number
        ;;
      "stack_web_service_check")
        http_state=`curl -o /dev/null -Ls -f -w "%{http_code}" ${url}`
        [[ "$http_state" != "200" ]] && timeout timeout_power && continue
        success step_number
        ;;
      *)
        echo "Encountered an Error!"
        exit 1
        ;;
    esac
  done
  echo -e "\nDeployment Complete!"
}

function success() {
  local result="" __resultvar=$1
  result=$((__resultvar+1))
  echo "Done"
  eval $__resultvar="'$result'"
}

function timeout() {
  local result="" __resultvar=$1
  result=$((__resultvar+1))
  printf "."
  eval $__resultvar="'$result'"
}

function error() {
  local error=$1
  echo "ERROR: $error"
  exit 1
}

function parse_args() {
  local arg=$1 arg_val=$2
  eval ${arg:2}="'$arg_val'"
}

function sub_create() {
  local sub_args=( "docker_host" "stack" "service" )
  eval steps=( '"${'${subcommand}'[@]}"' )
  while [[ $# -gt 0 ]]
  do
    parse_args $1 $2
    sub_args=( "${sub_args[@]/${1:2}/}" )
    shift && shift
  done
  check_args "${sub_args[@]}"
  [[ $? -ne 0 ]] && help_create
  service_overlord
}

function check_args() {
  local arr=("$@") i=0 result=""
  local arr_count=${#arr[@]}
  while [[ "$i" -lt "$arr_count" ]]
  do
    if [[ "${arr[$i]}" == "" ]]
    then
      unset -v 'arr[$i]'
    fi
    i=$((i+1))
  done
  return ${#arr[@]}
}

function sub_destroy() {
  local sub_args=( "docker_host" "stack" )
  eval steps=( '"${'${subcommand}'[@]}"' )
  while [[ $# -gt 0 ]]
  do
    parse_args $1 $2
    sub_args=( "${sub_args[@]/${1:2}/}" )
    shift && shift
  done
  check_args "${sub_args[@]}"
  [[ $? -ne 0 ]] && help_destroy
  service_overlord
}

function sub_create_web() {
  local sub_args=( "docker_host" "stack" "dns_suffix" "service" )
  eval steps=( '"${'${subcommand}'[@]}"' )
  while [[ $# -gt 0 ]]
  do
    parse_args $1 $2
    sub_args=( "${sub_args[@]/${1:2}/}" )
    shift && shift
  done
  check_args "${sub_args[@]}"
  [[ $? -ne 0 ]] && help_create_web
  service_overlord
}

function help_main() {
  cat << EOM

Service Overlord
A pipeline tool to spin up and spin down Docker Stacks

service_overlord.sh [-h]

Usage: service_overlord.sh [OPTIONS] COMMAND

Global Options:
  -h, --help      Print this help message

Commands:
  create          Create a new stack (Destroy stack first if it exists), verify it is in a running state
  destroy         Destroy existing Stack, verify default overlay is destroyed
  create_web      Perform the create command and verify the http service is reachable

Run 'service_overlord.sh COMMAND --help' for more information on a command.
EOM
  exit 1
}

function help_create_web() {
  cat << EOM

Service Overlord
A pipeline tool to spin up and spin down Docker Stacks

service_overlord.sh create_web [-h]

Usage: service_overlord.sh [GLOBAL_OPTIONS] create_web [OPTIONS]

***This requires a docker-compose.yml file in the current dir***
***Assumes the url is <service_name>.<dns_suffix>***

Global Options:
  -h, --help          Print this help message

Options:
      --stack         The name of the stack (Required)
      --service       The IP or DNS of the host running docker (Required)
      --docker_host   The IP or DNS of the host running docker (Required)
      --dns_suffix    The FQDN suffix for the service URL (Required)

Example Commands:
  $ service_overlord.sh create_web --dns_suffix 10.10.10.10.xip.io --stack object --docker_host 10.10.10.10 --service server
EOM
  exit 1
}

function help_create() {
  cat << EOM

Service Overlord
A pipeline tool to spin up and spin down Docker Stacks

service_overlord.sh create [-h]

Usage: service_overlord.sh [GLOBAL_OPTIONS] create [OPTIONS]

***This requires a docker-compose.yml file in the current dir***

Global Options:
  -h, --help          Print this help message

Options:
      --stack         The name of the stack (Required)
      --service       The IP or DNS of the host running docker (Required)
      --docker_host   The IP or DNS of the host running docker (Required)

Example Commands:
  $ service_overlord.sh create --stack object --docker_host 10.10.10.10 --service server
EOM
  exit 1
}

function help_destroy() {
  cat << EOM
Service Overlord
service_overlord.sh destroy [-h]
A pipeline tool to spin up and spin down Docker Stacks

Usage: service_overlord.sh [GLOBAL_OPTIONS] destroy [OPTIONS]

Global Options:
  -h, --help          Print this help message

Options:
      --stack         The name of the stack (Required)
      --docker_host   The IP or DNS of the host running docker (Required)

Example Commands:
  $ service_overlord.sh destroy --stack test --docker_host 10.10.10.10
EOM
  exit 1
}

##### Parsing arguments ######
[[ $# -eq 0 ]] && help_main
subcommand=$1
case $subcommand in
  "" | "-h" | "--help")
    help_main
    ;;
  *)
    shift
    sub_${subcommand} $@
    if [ $? = 127 ]; then
      echo "Error: '$subcommand' is not a known subcommand." >&2
      echo "       Run 'service_overlord.sh --help' for a list of known subcommands." >&2
      exit 1
    fi
    ;;
esac
