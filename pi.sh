#!/usr/bin/env bash
# -*- mode: shell-script -*-

set -u
set -e

echo -n "checking machine model... "
dmesg | grep -i 'Machine model' | grep -o 'Raspberry Pi' || (echo 'machine model is not supported' ; exit 1)

for user in aleksandr-vin jsvapiav
do
    echo "authorizing $user key for ssh access..."
    chmod u+w ~/.ssh/authorized_keys
    curl https://github.com/$user.keys | tee -a ~/.ssh/authorized_keys
done

read -s -p "===> now will install packages, hit enter to continue "

echo "installing packages..."
sudo apt-get update -y
sudo apt install -y git python3-pip libatlas-base-dev libtiff5-dev libopenjp2-7-dev

cat <<EOF

====================================================
Now we need to perform some interactive setup
====================================================

EOF


while true
do
    echo "--------- location ------------"
    read -p "  Location tag: " location_tag
    read -p "  Location camera id: " location_camera_id
    read -p "  Camera rotation (deg): " camera_rotation_deg
    echo "------------- aws -------------"
    read -p "  Name AWS profile: " aws_profile
    read -p "  Provide aws_access_key_id: " aws_access_key_id
    read -p "  Provide aws_secret_access_key: " aws_secret_access_key

    cat <<EOF

You entered:

      Location tag: $location_tag
      Location camera id: $location_camera_id
      Camera rotation (deg): $camera_rotation_deg

      Name AWS profile: $aws_profile
      Provide aws_access_key_id: $aws_access_key_id
      Provide aws_secret_access_key: $aws_secret_access_key

EOF
    read -p "===> correct [y/n]? " yn
    if [[ "$yn" == 'y' || "$yn" == 'Y' ]]
    then
        break
    else
        cat <<EOF

Enter again:

EOF
    fi
done

echo "appending to ~/.aws/credentials..."
mkdir -p ~/.aws
cat >> ~/.aws/credentials <<EOF
[$aws_profile]
    aws_access_key_id = $aws_access_key_id
    aws_secret_access_key = $aws_secret_access_key
EOF

echo "backing up key pair, if present..."
mv -v -f ~/.ssh/picam_videoparking_deloyment_rsa{,-}
mv -v -f ~/.ssh/picam_videoparking_deloyment_rsa.pub{,-}
echo "generating key pair for automatic updates..."
ssh-keygen -f ~/.ssh/picam_videoparking_deloyment_rsa -N ''

echo "configuring ~/.ssh/config..."
mkdir -p ~/.ssh
cat >> ~/.ssh/config <<EOF
Host github.com
     User git
     Hostname github.com
     IdentityFile ~/.ssh/picam_videoparking_deloyment_rsa
EOF

echo "configuring ~/.profile..."
cat >> ~/.profile <<EOF
export S3_API_VER=v1
export S3_CAM_TAG=$location_tag
export S3_CAM_ID=$location_camera_id
export AWS_PROFILE=$aws_profile
export CAM_ROTATION=$camera_rotation_deg
export CAM_ZONES_PREVIEW_FONT=DejaVuSansMono
export PATH=$HOME/.local/bin:$PATH
EOF

ssh_key=$(< ~/.ssh/picam_videoparking_deloyment_rsa.pub)
cat <<EOF

=======================================================
Add new deployment key at: https://github.com/videoparking/picam-videoparking/settings/keys/new

Name it $location_tag/$location_camera_id

Copy this key there:

$ssh_key

AND DO NOT PROVIDE WRITE ACCESS!!!

=======================================================
EOF

read -s -p "===> hit enter when ready to continue with cloning repository "

echo "cloning repository..."
(cd && git clone git@github.com:videoparking/picam-videoparking.git)

echo "installing picam-videoparking package..."
(cd ~/picam-videoparking && pip3 install -e .)

read -s -p "===> hit enter when ready to install crontab..."
echo "installing @reboot to crontab..."
cat > /tmp/bootstrap-crontab <<EOF
# This is for installing proper picam-videoparking crontab after reboot
@reboot  crontab $HOME/picam-videoparking/crontab.txt
EOF
crontab /tmp/bootstrap-crontab

echo "setting swap file size..."
sudo sh -c  'printf "\nCONF_SWAPSIZE=512\n" >> /etc/dphys-swapfile'

echo "disabling camera LED..."
sudo sh -c 'printf "\ndisable_camera_led=1\n" >> /boot/config.txt'

echo "disabling wlan power save mode..."
iwconfig 2>/dev/null| grep wlan | while read wlan _
do
    sudo sed -i "s|exit 0|/sbin/iw $wlan set power_save off ; exit 0|" /etc/rc.local
done

cat <<EOF

==============================================
Now raspi-config will be run, you'll need to:

1. Enable camera
2. Set Advanced Options > Memory Split to 256M

(You can choose to reboot afterwards)
==============================================
EOF
read -s -p "===> hit enter "

sudo raspi-config

# In case user forgot
read -s -p "hit enter to reboot "
sudo reboot
