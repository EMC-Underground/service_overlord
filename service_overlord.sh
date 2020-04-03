#!/bin/sh

# Available sub commands
sub_commands=( "create" "destroy" "create_web" )

# Create sub command details
create_steps=( "stack_check" "stack_cleanup" "network_cleanup" \
  "stack_volume_check" "stack_volume_remove" "volume_cleanup" "stack_deploy" \
  "stack_deploy_check" )
create_args=( "docker_host" "stack" "service" )

# Create_web sub command details
create_web_steps=( "stack_check" "stack_cleanup" "network_cleanup" \
  "stack_volume_check" "stack_volume_remove" "volume_cleanup" "stack_deploy" \
  "stack_deploy_check" "stack_web_stack_check" )
create_web_args=( "docker_host" "stack" "dns_suffix" "service" )

# Destroy sub command details
destroy_steps=( "stack_check" "stack_cleanup" "network_cleanup" \
  "stack_volume_check" "stack_volume_remove" "volume_cleanup" )
destroy_args=( "docker_host" "stack" )

function service_overlord() {
  local step_number=0 timeout_power=2 timeout_power_limit=7 timeout_value=2
  local current_step="" ERROR="" url="http://${stack}.${dns_suffix}"
  export DOCKER_HOST=$docker_host
  export DNS_SUFFIX=$dns_suffix
  while [ "$step_number" -lt "${#steps[@]}" ] && \
    [ "$timeout_power" -lt "$timeout_power_limit" ]
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
        [[ $? -ne 0 ]] && \
          step_number=$((step_number+3)) && \
          echo "Done" && \
          continue
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
        { ERROR=$( { docker stack deploy -c docker-compose.yml \
          $stack ; } 2>&1 ); } 3>&1
        [[ $? -ne 0 ]] && error "$ERROR"
        success step_number
        ;;
      "stack_deploy_check")
        service_state=`docker service ps ${stack}_${service} \
          | awk 'FNR == 2 {print $6}'`
        [[ $service_state != "Running" ]] && timeout timeout_power && continue
        success step_number
        ;;
      "stack_web_stack_check")
        http_state=`curl -o /dev/null -Ls -f -w "%{http_code}" ${url}`
        [[ "$http_state" != "200" ]] && timeout timeout_power && continue
        success step_number
        ;;
      "stack_volume_check")
        docker volume ls | grep "${stack}_${service}-data" > /dev/null 2>&1
        [[ $? -ne 0 ]] && \
          step_number=$((step_number+3)) && \
          echo "Done" && \
          continue
        success step_number
        ;;
      "stack_volume_remove")
        { ERROR=$( {docker volume rm ${stack}_${service}-data ; } 2>&1 ); } 3>&1
        [[ $? -ne 0 ]] && error "$ERROR"
        success step_number
        ;;
      "volume_cleanup")
        docker network ls | grep "${stack}_default" > /dev/null 2>&1
        [[ $? -eq 0 ]] && timeout timeout_power && continue
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

function sub_main() {
  eval sub_args=( '"${'${subcommand}'_args[@]}"' )
  eval steps=( '"${'${subcommand}_steps'[@]}"' )
  while [[ $# -gt 0 ]]
  do
    [[ "$1" == "-h" ]] && help_${subcommand}
    [[ ! " ${sub_args[@]} " =~ " ${1:2} " ]] && \
      echo -e "Invalid Argument: $1\n" && \
      help_${subcommand}
    parse_args $1 $2
    sub_args=( "${sub_args[@]/${1:2}/}" )
    shift && shift
  done
  check_args "${sub_args[@]}"
  [[ $? -ne 0 ]] && \
    echo "Missing arguments:${sub_args[@]}" && \
    help_${subcommand}
  service_overlord
}

function help_main() {
  cat << EOM

Service Overlord
A pipeline tool to spin up and spin down Docker Stacks

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

Create a new web stack and wait until it is responding

Usage: service_overlord.sh [GLOBAL_OPTIONS] create_web [OPTIONS]

  1. This requires a docker-compose.yml file in the current dir
  2. Assumes the url is <stack_name>.<dns_suffix>

Global Options:
  -h, --help          Print main help message

Options:
      --stack         The name of the stack (Required)
      --service       The name of the service (Required)
      --docker_host   The IP or DNS of the host running docker (Required)
      --dns_suffix    The FQDN suffix for the service URL (Required)
  -h, --help          Print this help message

Example Commands:
  $ service_overlord.sh create_web --dns_suffix 10.10.10.10.xip.io --stack object --docker_host 10.10.10.10 --service server
EOM
  exit 1
}

function help_create() {
  cat << EOM

Create a new stack and wait until it is in a running state

Usage: service_overlord.sh [GLOBAL_OPTIONS] create [OPTIONS]

  1. This requires a docker-compose.yml file in the current dir

Global Options:
  -h, --help          Print main help message

Options:
      --stack         The name of the stack (Required)
      --service       The name of the service (Required)
      --docker_host   The IP or DNS of the host running docker (Required)
  -h, --help          Print this help message

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
  -h, --help          Print main help message

Options:
      --stack         The name of the stack (Required)
      --docker_host   The IP or DNS of the host running docker (Required)
  -h, --help          Print this help message

Example Commands:
  $ service_overlord.sh destroy --stack test --docker_host 10.10.10.10
EOM
  exit 1
}

##### Parsing arguments ######
[[ $# -eq 0 ]] && help_main
[[ ! " ${sub_commands[@]} " =~ " $1 " ]] && \
  echo -e "Invalid Sub Command: $1" && \
  help_main
subcommand=$1
case $subcommand in
  "" | "-h" | "--help")
    help_main
    ;;
  *)
    shift
    sub_main $@
    ;;
esac
