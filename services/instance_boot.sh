#!/bin/bash
## Example boot/creation of an instance
# run this as vagrant@controller0
 
source ${BASH_SOURCE%/*}/../defaults.sh

## boot a new instance as the non-admin user
# we assume an image and key from our glance and nova installer scripts
IMAGE_ID=`nova image-list | awk '/\ CirrOS\ / {print $2}'`
NET_ID=`neutron net-list | awk "/${DEMO_TENANT_NAME}-net/ {print \\$2}"`
# we'll name the instance for the non-admin user
RAND=`< /dev/urandom tr -dc a-z0-9 | head -c3`
INSTANCE_NAME="${OS_TENANT_NAME}_${RAND}"
INSTANCE_ID=`OS_USERNAME=$OS_TENANT_NAME nova boot ${INSTANCE_NAME} \
  --image ${IMAGE_ID} --flavor 1 --key-name vagrant \
  --security-group default --nic net-id=${NET_ID} \
  | awk '$2 == "id" {print $4}'`

# grab its IP addr
# TODO get rid of the hard-coded addr in the sed regex
count=3
INSTANCE_IP=''
while [ -z "$INSTANCE_IP" ] &&  (( count-- > 0 )); do
  echo "I'll try $(( count + 1 )) more times..."
  sleep 5
  INSTANCE_IP=`nova show $INSTANCE_ID \
    | awk '/\ network.*10\.0\.1\./ {print}' | sed 's|.*\(10\.0\.1\.[[:digit:]+]\).*|\1|'`
done


## give ourselves a chance to see it boot
if [ -n "$INSTANCE_IP" ]; then
  nova show $INSTANCE_ID

  # give it a floating IP
  FLOATING_IP=`OS_USERNAME=$OS_TENANT_NAME neutron floatingip-create ext-net \
  | awk '$2 == "floating_ip_address" {print $4}'`
  if [ -n "$FLOATING_IP" ]; then
    nova floating-ip-associate ${INSTANCE_NAME} ${FLOATING_IP}
  fi

  ## create a volume named for the instance
  # delete any old ones, though there should be none
  for id in `cinder list --display-name ${INSTANCE_NAME} | awk "/\ ${INSTANCE_NAME}/ {print \$2}"`; do
    cinder delete $id
  done

  # create a 1GB volume
  VOLUME_ID=`cinder create --display-name ${INSTANCE_NAME} 1 \
    | awk '$2 == "id" {print $4}'`

  # attach the volume, letting the instance choose local device (auto)
  sleep 20 # somebody shoot me, but the instance needs time to build
  nova volume-attach $INSTANCE_ID $VOLUME_ID auto
  nova volume-show $VOLUME_ID

  echo "Waiting for ${INSTANCE_NAME} to boot..."
  nova get-vnc-console ${INSTANCE_NAME} novnc
  sleep 20
  echo "Whistle a happy tune and give ssh a chance to start on ${FLOATING_IP}..."
  echo
  # echo "From the network node, 'ip netns list | grep dhcp' to find the namespace id, then"
  # echo "'ip netns exec <namespace id> ssh cirros@${INSTANCE_IP}' with passwd 'cubswin:)'"
  echo "...then \"ssh -o 'IdentityFile ~/.ssh/vagrant.pem' cirros@${FLOATING_IP}\""
  echo
else
  echo "No IP address was found for instance ${INSTANCE_NAME} (${INSTANCE_ID})"
fi

