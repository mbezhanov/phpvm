# PHP Version Manager

**phpvm** (short for "PHP Version Manager") is a simple bash script for managing PHP versions, inspired by [NVM](https://github.com/creationix/nvm) and powered by [Docker](https://www.docker.com/).


**phpvm** uses Docker images and containers to enable seamless switching between PHP versions for local development. It can also be used to build highly-customized production-ready PHP Docker images.

## Installation

To install **phpvm**, simply download `phpvm.sh` and put it in your path.

```bash
wget https://github.com/mbezhanov/phpvm/archive/master.zip
unzip -p master.zip phpvm-master/phpvm.sh > phpvm
mv phpvm /usr/local/bin
chmod +x /usr/local/bin/phpvm
``` 

At this point you should be able to call `phpvm` from your command line.

## Quickstart

Simply typing `phpvm` in your console, without any arguments, will list all of the available commands.

To use a particular PHP version with your project, navigate to your project root, then run:

```
phpvm use <version>
```

...where `<version>` can be any tag available in the [PHP Official Docker Image](https://hub.docker.com/_/php?tab=tags)

For example, if you'd like to run PHP 7.3.6, you can do something like:

```
phpvm use 7.3.6-cli-alpine
```

This will automatically pull the corresponding image from Docker Hub and start a new container from it, mounting your project root to `/src` inside the container and installing the latest version of Composer in the process. 

You can use `phpvm root` to open a terminal for interacting with your container as the `root` user. This will allow you to tweak the PHP configuration, add specific extensions, or install additional Linux packages. **phpvm** will remember your changes and associate them with the selected PHP version. Next time you run `phpvm use 7.3.6-cli-alpine`, you can count on finding the same set of configuration settings, extensions and Linux packages available.

To open a terminal for interacting with your container as the currently logged in user, you can type `phpvm tty`. This is suitable for running `composer install`, `composer update` or any other console scripts and commands related to your project, as it retains the file and directory permissions of your current user.

When you're done using your container, you can optionally type `phpvm deactivate` to switch it off.
