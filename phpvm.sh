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
  sudo docker image ls --format "{{.Repository}}-{{.Tag}}\t{{.ID}}" | grep -P "^$1\t" | awk '{print $2}'
}

phpvm_get_image_name() {
  sudo docker image ls --format "{{.Repository}}-{{.Tag}}\t{{.Repository}}:{{.Tag}}" | grep -P "^$1\t" | awk '{print $2}'
}

phpvm_get_running_container_id() {
  local CONTAINER_ID=$(sudo docker container ls --filter name=phpvm --filter "status=running" --format "{{.ID}}")
  phpvm_echo "$CONTAINER_ID"
}

phpvm_get_running_container_image() {
  local CONTAINER_IMAGE=$(sudo docker container ls --filter name=phpvm --filter "status=running" --format "{{.Image}}")
  phpvm_echo "$CONTAINER_IMAGE"
}

phpvm_determine_shell_type() {
  local SHELL_TYPE=bash

  case "$1" in 
    *alpine*)
      SHELL_TYPE=ash
    ;;
  esac

  phpvm_echo $SHELL_TYPE
}

phpvm_ensure_composer_installed() {
  local CONTAINER_ID=$(phpvm_get_running_container_id)
  local COMPOSER_INSTALLED=$(sudo docker container exec $CONTAINER_ID which composer)

  if [ ! -z "$COMPOSER_INSTALLED" ]; then
    return $PHPVM_SUCCESS
  fi

  local UPDATE_COMMAND='apt-get update'
  local INSTALL_COMMAND='apt-get install -y'

  case "$1" in
    *alpine*)
      UPDATE_COMMAND='apk update'
      INSTALL_COMMAND='apk add --no-cache'
    ;;
  esac

  # install required Linux libraries
  sudo docker container exec $CONTAINER_ID $UPDATE_COMMAND \
    && sudo docker container exec $CONTAINER_ID $INSTALL_COMMAND unzip libzip-dev

  # These PHP extensions are required by the Laravel framework and its installer. Symfony works with the default extensions.
  sudo docker container exec $CONTAINER_ID docker-php-ext-install bcmath zip

  # go on with Composer installation:
  local EXPECTED_SIGNATURE="$(wget -q -O - https://composer.github.io/installer.sig)"
  sudo docker container exec $CONTAINER_ID php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
  local ACTUAL_SIGNATURE=$(sudo docker container exec $CONTAINER_ID php -r "echo hash_file('sha384', 'composer-setup.php');")

  if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]; then
    sudo docker container exec $CONTAINER_ID rm composer-setup.php
    return $PHPVM_FAIL
  fi

  sudo docker container exec $CONTAINER_ID php composer-setup.php --no-ansi --install-dir=/usr/local/bin --filename=composer \
    && sudo docker container exec $CONTAINER_ID composer --version \
    && sudo docker container exec $CONTAINER_ID rm composer-setup.php \
    && sudo docker container exec $CONTAINER_ID mkdir -p /usr/local/composer/repo/https---repo.packagist.org /usr/local/composer/files \
    && sudo docker container exec $CONTAINER_ID chmod -R a+w /usr/local/composer
}

phpvm_use() {
  local CONTAINER_NAME=$(phpvm_container_name "$1")
  phpvm_remove_dangling_containers
  local NEEDED_IMAGE_ID=$(phpvm_get_image_id $CONTAINER_NAME)
  
  if [ -z "$NEEDED_IMAGE_ID" ]; then
    sudo docker image pull php:$1 && sudo docker image tag php:$1 phpvm:$1
  fi

  local SHELL_TYPE=$(phpvm_determine_shell_type "$CONTAINER_NAME")
  sudo docker container run \
    --name $CONTAINER_NAME \
    -e "COMPOSER_HOME=/usr/local/composer" \
    -e "COMPOSER_ALLOW_SUPERUSER=1" \
    -v $(pwd):/src \
    --workdir /src \
    -dt phpvm:$1 $SHELL_TYPE
  
  if ! phpvm_ensure_composer_installed "$CONTAINER_NAME"; then
    phpvm_err 'phpvm was unable to install Composer automatically'
  fi
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
  if [ -z "$CONTAINER_NAME" ]; then
    return $PHPVM_FAIL
  fi
  local IMAGE_NAME=$(phpvm_get_image_name $CONTAINER_NAME)
  if [ -z "$IMAGE_NAME" ]; then
    phpvm_err "PHP $1 is not installed."
    return $PHPVM_FAIL
  fi

  phpvm_remove_dangling_containers && sudo docker image rm $IMAGE_NAME
}

phpvm_ensure_user_exists() {
  if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
    return $PHPVM_FAIL
  fi

  local CONTAINER_ID=$(phpvm_get_running_container_id)
  local CONTAINER_IMAGE=$(phpvm_get_running_container_image)
  local SHELL_TYPE=$(phpvm_determine_shell_type "$CONTAINER_IMAGE")
  local USER_ENTRY="$3:x:$1:$2:$3:/src:/bin/$SHELL_TYPE"
  local USER_EXISTS=$(sudo docker container exec $CONTAINER_ID grep ":x:$1:" /etc/passwd)
  local GROUP_ENTRY="$4:x:$2:"
  local GROUP_EXISTS=$(sudo docker container exec $CONTAINER_ID grep ":x:$2:" /etc/group)

  if [ -z "$USER_EXISTS" ]; then
    sudo docker container exec $CONTAINER_ID sh -c "echo \"$USER_ENTRY\" >> /etc/passwd"
  fi

  if [ -z "$GROUP_EXISTS" ]; then
    sudo docker container exec $CONTAINER_ID sh -c "echo \"$GROUP_ENTRY\" >> /etc/group"
  fi
}

phpvm_container_open_terminal() {
  local CONTAINER_ID=$(phpvm_get_running_container_id)

  if [ -z "$CONTAINER_ID" ]; then
    phpvm_err 'PHP is not running.'
    return $PHPVM_FAIL
  fi
  local CONTAINER_IMAGE=$(phpvm_get_running_container_image)
  local SHELL_TYPE=$(phpvm_determine_shell_type "$CONTAINER_IMAGE")
  local USER_FLAG

  if [ ! -z "${1-}" ]; then
    USER_FLAG="--user $1"
  fi

  sudo docker container exec -it $USER_FLAG --privileged $CONTAINER_ID $SHELL_TYPE
}

phpvm_tty() {
  local USER_ID=$(id -u)
  local GROUP_ID=$(id -g)
  local USER_NAME=$(id -un)
  local GROUP_NAME=$(id -gn)

  if phpvm_ensure_user_exists "$USER_ID" "$GROUP_ID" "$USER_NAME" "$GROUP_NAME"; then
    phpvm_container_open_terminal "$USER_ID:$GROUP_ID"
  fi
}

phpvm_root() {
  phpvm_container_open_terminal
}

phpvm_deactivate() {
  local CONTAINER_ID=$(phpvm_get_running_container_id)

  if [ -z "$CONTAINER_ID" ]; then
    phpvm_err 'PHP is not running.'
    return $PHPVM_FAIL
  fi

  phpvm_remove_dangling_containers
}

phpvm_print_usage_info() {
  phpvm_echo
  phpvm_echo 'PHP Version Manager (v0.4.1)'
  phpvm_echo
  phpvm_echo 'Usage:'
  phpvm_echo '  phpvm ls            List all installed PHP versions'
  phpvm_echo '  phpvm use <version> Install and use a particular PHP version'
  phpvm_echo '  phpvm rm <version>  Remove an installed PHP version'
  phpvm_echo '  phpvm tty           Open a terminal for interacting with the active PHP version as the current user'  
  phpvm_echo '  phpvm root          Open a terminal for interacting with the active PHP version as root'
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
    "root")
      phpvm_root
    ;;
    "deactivate")
      phpvm_deactivate
    ;;
  esac
}

phpvm_parse_arguments "$@"
