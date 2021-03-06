#!/bin/sh

# https://docs.saltstack.com/en/latest/ref/configuration/index.html
# https://docs.saltstack.com/en/latest/topics/installation/ubuntu.html
# https://repo.saltstack.com/#ubuntu


usage() {
  echo "Usage: setup-salt.sh <master|minion [master-IP]>"
  echo
  echo "Arguments:"
  echo "  master              This computer is a salt master server"
  echo "  minion [master-IP]  This computer is a salt minion"
  echo "                      You optionally can provide a master IP address"
  echo "                      If not, salt will default to 'salt' as master"
  echo "                      server hostname"
  echo
  echo "You can run this script on both server and client at the same time, "
  echo "they will wait for user input at neuralgic steps."
  echo "This script must be run as root."
}


die() {
  printf "ERROR: $1\n"
  exit 1
}

setup_repos() {
  # setup repos
  wget -O - https://repo.saltstack.com/apt/ubuntu/16.04/amd64/2016.3/SALTSTACK-GPG-KEY.pub | apt-key add - 

  echo "deb http://repo.saltstack.com/apt/ubuntu/16.04/amd64/2016.3 xenial main" > \
    /etc/apt/sources.list.d/saltstack.list

  apt-get update > /dev/null
}


if [ $(whoami) != "root" ]; then
  echo "you must be root to execute this file."
  exit 1
fi

# Setup for both, master + minion




# Master setup
if  [ "$1" = "master" ]; then

  setup_repos

  # Installing salt-master if not already installed
  dpkg -l salt-master >/dev/null || apt-get install salt-master -y > /dev/null

  masterkey=$(salt-key  -F master |grep master.pub | cut -d " " -f3)

  if [ "$masterkey" = "" ]; then
    die "Master key could not be retrieved."
  fi

  echo "Please run this script now at a salt minion (ore more) and enter this key when asked:"
  echo
  echo "   $masterkey"
  echo
  echo "When all clients are finished, Press [Enter]."
  read yn

  # Retrieve all keys from clients that are connected
  unaccepted_hosts=`salt-key --list un|grep -v "Unaccepted Keys" | xargs`

  for host in $unaccepted_hosts; do
    key=`salt-key --finger=$host | sed "s/$host:  //" | egrep "^([0-9a-f]{2}:){15}[0-9a-f]{2}$"`
    yn=
    read -p "Accept host '$host' with key '$key'? [Y/n]" yn
    if [ "$yn" = "y" -o "$yn" = "Y" -o "$yn" = "" ]; then
      salt-key -a $host -y
    fi
  done

  echo "Finished."

# Minion setup
elif [ "$1" = "minion" ]; then

  setup_repos

  dpkg -l salt-minion >/dev/null || apt-get install salt-minion -y

  minion_config_file="/etc/salt/minion"
  if [ ! -f $minion_config_file ]; then
    die "Minion config file $minion_config_file was not found.\nPlease check that salt-minion is correctly installed."
  fi

  echo "Please enter the master fingerprint of the server. You can get it"
  echo "running this script there, or by calling 'salt -F master' on the server."
  echo "The fingerprint must be in the format XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX:XX to"
  echo "be accepted."
  echo -n "Server fingerprint: "

  masterkey=
  while [ a$(echo "$masterkey"|xargs) = "a" ]; do
    read masterkey
    # basically validate fingerprint string...
    masterkey=`echo $masterkey | xargs| egrep "^([0-9a-f]{2}:){15}[0-9a-f]{2}$"`
  done

  line=`egrep "^#?master_finger: *'.*' *$" $minion_config_file`
  if egrep "^ *master_finger: *'$masterkey' *$" $minion_config_file; then

    echo "Master key fingerprint is already in the salt minion config present. Skipping."

  elif [ "$line" != ""  ]; then
    echo "Replacing 'master_finger' option in minion config..."
    sed -i -e "s/^#?master_finger: *'.*' *$/master_finger: '$masterkey'/" $minion_config_file
  fi


  # get the local fingerprint, extract and trim it
  fingerprint=`salt-call --local key.finger | egrep "^ *([0-9a-f]{2}:){15}[0-9a-f]{2}$" | xargs`
  if [ "$fingerprint" = "" ]; then
    die "Minion fingerprint could not be correctly parsed."
  fi

  if [ "$2" = "" ]; then
    master="salt"
  else
    master="$2"
  fi

  ping -c1 $master >/dev/null || die "Master '$master' is not reachable in the network."

  # Update master IP in the minion config file
  sed -i -e "s/^ *#? *master:.*$/master: $2/" $minion_config_file

  # restart salt-minion so that changes can take effect
  systemctl restart salt-minion.service

  printf "Finished.\nYou can now proceed with the script on the server, accepting the the fingerprint $fingerprint there."

else
  printf "ERROR: no argument given.\n"
  usage
  exit 1
fi
