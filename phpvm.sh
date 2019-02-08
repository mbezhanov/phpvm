#!/usr/bin/env bash
PHPVM_SUCCESS=0
PHPVM_FAIL=1

phpvm_echo() {
  command printf %s\\n "$*" 2>/dev/null
}

phpvm_err() {
  >&2 phpvm_echo "$@"
}

phpvm_container_name() {
  if [ -z "$1" ]; then
    phpvm_err 'PHP version not specified'
    return $PHPVM_FAIL
  fi

  phpvm_echo "phpvm-$1"
}

phpvm_save_images_changes() {
  local CONTAINER_IMAGE=$(sudo docker container ls -a --filter "id=$1" --format "{{.Image}}")
  local CONTAINER_IMAGE_REPO=$(phpvm_echo $CONTAINER_IMAGE | tr ":" "\t" | awk '{print $1}')
  local CONTAINER_IMAGE_TAG=$(phpvm_echo $CONTAINER_IMAGE | tr ":" "\t" | awk '{print $2}')
  local CONTAINER_IMAGE_ID=$(sudo docker image ls | grep $CONTAINER_IMAGE_REPO | grep $CONTAINER_IMAGE_TAG | awk '{print $3}')
  local HAS_CHANGES=$(sudo docker container diff $1 | egrep -v '(/src|/root)' | wc -l)

  if [ $HAS_CHANGES -eq 0 ]; then
    # no changes for saving
    return $PHPVM_SUCCESS
  fi

  sudo docker container commit $1 $CONTAINER_IMAGE_REPO:$CONTAINER_IMAGE_TAG
}

phpvm_remove_dangling_containers() {
  local CONTAINER_IDS=$(sudo docker container ls -a --format "{{.ID}}" --filter "name=^phpvm" | awk '{print $1}' | tr '\n' ' ')

  if [ -z "$CONTAINER_IDS" ]; then
    return $PHPVM_SUCCESS
  fi

  for CONTAINER_ID in $CONTAINER_IDS; do
    sudo docker container stop -t 1 $CONTAINER_ID
    phpvm_save_images_changes "$CONTAINER_ID"
    sudo docker container rm $CONTAINER_ID
  done
}

phpvm_get_image_id() {
  sudo docker image ls --format "{{.Repository}}-{{.Tag}}\t{{.ID}}" | grep $1 | awk '{print $2}'
}

phpvm_get_image_name() {
  sudo docker image ls --format "{{.Repository}}-{{.Tag}}\t{{.Repository}}:{{.Tag}}" | grep $1 | awk '{print $2}'
}

phpvm_use() {
  local CONTAINER_NAME=$(phpvm_container_name "$1")
  phpvm_remove_dangling_containers
  local NEEDED_IMAGE_ID=$(phpvm_get_image_id $CONTAINER_NAME)
  
  if [ -z "$NEEDED_IMAGE_ID" ]; then
    sudo docker image pull php:$1 && sudo docker image tag php:$1 phpvm:$1
  fi

  local SHELL_TYPE=bash

  case "$CONTAINER_NAME" in 
    *alpine*)
      SHELL_TYPE=ash
    ;;
  esac

  sudo docker container run --name $CONTAINER_NAME -v $(pwd):/src --workdir /src -dt phpvm:$1 $SHELL_TYPE
}

phpvm_ls() {
  local INSTALLED_VERSIONS=$(sudo docker image ls --format "{{.Repository}}:\t{{.Tag}}" | grep ^phpvm: | awk '{print $2}')

  if [ -z "$INSTALLED_VERSIONS" ]; then
    phpvm_echo
    phpvm_echo "No PHP versions installed."
    phpvm_echo
    return
  fi

  phpvm_echo
  phpvm_echo 'Installed PHP versions:'
  phpvm_echo
  phpvm_echo "$INSTALLED_VERSIONS"
  phpvm_echo
}

phpvm_rm() {
  local CONTAINER_NAME=$(phpvm_container_name "$1")
  if [ -z $CONTAINER_NAME ]; then
    return $PHPVM_FAIL
  fi
  local IMAGE_NAME=$(phpvm_get_image_name $CONTAINER_NAME)
  if [ -z $IMAGE_NAME ]; then
    phpvm_err "PHP $1 is not installed."
    return $PHPVM_FAIL
  fi

  phpvm_remove_dangling_containers && sudo docker image rm $IMAGE_NAME
}

phpvm_tty() {
  local CONTAINER_ID=$(sudo docker container ls --filter name=phpvm --filter "status=running" --format "{{.ID}}")

  if [ -z "$CONTAINER_ID" ]; then
    phpvm_err 'PHP is not running.'
    return $PHPVM_FAIL
  fi
  local CONTAINER_NAME=$(sudo docker container ls --filter name=phpvm --filter "status=running" --format "{{.Image}}")
  local SHELL_TYPE=bash

  case "$CONTAINER_NAME" in 
    *alpine*)
      SHELL_TYPE=ash
    ;;
  esac

  sudo docker container exec -it $CONTAINER_ID $SHELL_TYPE
}

phpvm_deactivate() {
  local CONTAINER_ID=$(sudo docker container ls --filter name=phpvm --filter "status=running" --format "{{.ID}}")

  if [ -z "$CONTAINER_ID" ]; then
    phpvm_err 'PHP is not running.'
    return $PHPVM_FAIL
  fi

  phpvm_remove_dangling_containers
}

phpvm_print_usage_info() {
  phpvm_echo
  phpvm_echo 'PHP Version Manager (v0.2.0)'
  phpvm_echo
  phpvm_echo 'Usage:'
  phpvm_echo '  phpvm ls            List all installed PHP versions'
  phpvm_echo '  phpvm use <version> Install and use a particular PHP version'
  phpvm_echo '  phpvm rm <version>  Remove an installed PHP version'
  phpvm_echo '  phpvm tty           Open a terminal for interacting with the active PHP version'  
  phpvm_echo '  phpvm deactivate    Deactivate the current active PHP version'      
  phpvm_echo
  phpvm_echo 'Example:'
  phpvm_echo '  phpvm use 7.3-cli-alpine  Install and use a specific PHP version'
  phpvm_echo '  phpvm rm 7.3-cli-alpine   Remove a specific PHP version'
  phpvm_echo
}

phpvm_parse_arguments() {
  if [ $# -lt 1 ]; then
    phpvm_print_usage_info
    return
  fi

  case "$1" in
    "ls")
      phpvm_ls
    ;;
    "rm")
      phpvm_rm $2
    ;;
    "use")
      phpvm_use $2
    ;;
    "tty")
      phpvm_tty
    ;;
    "deactivate")
      phpvm_deactivate
    ;;
  esac
}

phpvm_parse_arguments $@
