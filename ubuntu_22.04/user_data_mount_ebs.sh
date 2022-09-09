#!/bin/bash

#Install awscli
apt update
apt install unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

#install nvme-cli if needed
NVME=`which nvme`;
if [ $? -gt 0 ]; then
   apt install nvme-cli -y
   NVME=`which nvme`;
fi

UDEVD="/etc/udev/rules.d"

# Get the volume ID mapping to device name in console
REGION=`curl http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}'`
INSTANCEID=`curl http://169.254.169.254/latest/meta-data/instance-id`
AWSOUT=`aws ec2 describe-instances --instance-ids $INSTANCEID --region $REGION --query 'Reservations[*].Instances[*].BlockDeviceMappings[*].[Ebs.VolumeId,DeviceName]' --output text | awk '{print  $1","$2}'`;

# Create the udev rule file#
for item in $AWSOUT; do

   VOL=`echo "$item" | cut -d\, -f1| sed 's/\-//'`
   DEV=`echo "$item" | cut -d\, -f2| cut -d\/ -f3`
   
   echo "KERNEL==\"nvme[0-9]*n[0-9]*\", ENV{DEVTYPE}==\"disk\", ATTRS{model}==\"Amazon Elastic Block Store\", ATTRS{serial}==\"$VOL\", PROGRAM=\"$NVME id-ctrl /dev/%k\", SYMLINK+=\"$DEV\"" >> $UDEVD/30-ebs.rules
done

udevadm control --reload-rules
udevadm trigger

sleep 10

# Format the devices using the Xen-type names if not the root volume
for device in $AWSOUT; do

   DEVICE=`echo "$device" | cut -d\, -f2`
   if [ $DEVICE != "/dev/sda1" ]; then
       mkfs.ext4 $DEVICE
   fi

done

# Create mount points
mkdir /test01
mkdir /test02


# Mount the filesystems using the Xen-type names
mount /dev/sdb /test01
mount /dev/sdc /test02
