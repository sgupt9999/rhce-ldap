#!/bin/bash
#
#
# Configure OpenLDAP client on Centos 7

# Start of user inputs
####################################################################################
ENABLEHOMEDIR="yes"
#ENABLEHOMEDIR="no"

AUTOMASTERFILE="/etc/auto.master"
AUTOFSTIMEOUT=60
AUTOMAPFILE="/etc/auto.map"

####################################################################################
# End of user inputs


if (( $EUID != 0 )); then
	echo "ERROR: You need to run as root"
	exit 1
else
	echo "#########################################################################################"
	echo "This script will install OpenLDAP client on this machine"
	echo "#########################################################################################"
	sleep 5
	
fi

source ./inputs.sh
INSTALLPACKAGES="openldap-clients nss-pam-ldapd autofs"

if yum list installed autofs > /dev/null 2>&1
then
	systemctl -q is-active autofs && {
	systemctl stop autofs
	systemctl -q disable autofs
	}

	echo "Removing packages........................"
	yum remove -y $INSTALLPACKAGES
	rm -rf $AUTOMAPFILE
	echo "Done"
fi

# Add the server and client host names to /etc/hosts
sed -i "s/.*$IPSERVER.*/#&/g" $HOSTS
sed -i "s/.*$IPCLIENT.*/#&/g" $HOSTS
echo "$IPSERVER $HOSTSERVER" >> $HOSTS
echo "$IPCLIENT $HOSTCLIENT" >> $HOSTS

echo "Installing $INSTALLPACKAGES..........."
yum install -y $INSTALLPACKAGES
echo "Done"

# To use nslcd (instead of sssd)
authconfig --disableforcelegacy --update
authconfig --enableforcelegacy --update

if [[ $ENABLEHOMEDIR == "yes"  ]]
then
	authconfig --disableldap --disableldapauth --ldapserver=$IPSERVER \
	--ldapbasedn=dc=$DC1,dc=$DC2 --disablemkhomedir --update
	authconfig --enableldap --enableldapauth --ldapserver=$IPSERVER \
	--ldapbasedn=dc=$DC1,dc=$DC2 --enablemkhomedir --update
else
	authconfig --disableldap --disableldapauth --ldapserver=$IPSERVER \
	--ldapbasedn=dc=$DC1,dc=$DC2 --update
	authconfig --enableldap --enableldapauth --ldapserver=$IPSERVER \
	--ldapbasedn=dc=$DC1,dc=$DC2 --update
fi

systemctl start nslcd
systemctl enable nslcd

exit 1

# Configure Master file
echo "/home/guests	/etc/auto.map --timeout=$AUTOFSTIMEOUT" > $AUTOMASTERFILE
# Configure map file
echo "* -fstype=auto $IPSERVER:/home/&" > $AUTOMAPFILE


if [[ $CONFIGURETLS == "yes" ]]
then
	scp user@$IPSERVER:/etc/pki/tls/certs/$DC1.key /etc/openldap/certs/
	authconfig --enableldaptls --update
fi

systemctl start autofs
systemctl enable autofs
systemctl start nslcd
systemctl enable nslcd

echo "#######################################################################"
echo "OpenLDAP client successfully created"
echo "#######################################################################"
