#!/bin/bash
# This script will configure openldap client on Centos/RHEL 7 with diff security options
####################################################################################
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
	echo
	echo "##########################################################"
	echo "ERROR. You need to have root privileges to run this script"
	echo "##########################################################"
	exit 1
else
	echo
	echo "########################################################"
	echo "This script will install OpenLDAP client on this machine"
	echo "########################################################"
	sleep 5
	
fi

source ./inputs.sh
INSTALLPACKAGES1="openldap-clients nss-pam-ldapd"

if yum list installed nss-pam-ldapd > /dev/null 2>&1
then
	echo
	echo "#################"
	echo "Removing packages"
	yum remove -y -q $INSTALLPACKAGES1 > /dev/null 2>&1
	echo "Done"
	echo "#################"
fi

# Add the server and client host names to /etc/hosts
sed -i "s/.*$IPSERVER.*/#&/g" $HOSTS
sed -i "s/.*$IPCLIENT.*/#&/g" $HOSTS
echo "$IPSERVER $HOSTSERVER" >> $HOSTS
echo "$IPCLIENT $HOSTCLIENT" >> $HOSTS

echo
echo "#########################################"
echo "Installing $INSTALLPACKAGES1"
yum install -y -q $INSTALLPACKAGES1 > /dev/numm 2>&1
echo "Done"
echo "#########################################"
sleep 5

systemctl start nslcd
systemctl -q enable nslcd

# To use nslcd (instead of sssd)
authconfig --disableforcelegacy --update
authconfig --enableforcelegacy --update

if [[ $ENABLEHOMEDIR == "yes"  ]]
then
	if [[ $CONFIGURETLS == "yes" ]]
	then
		authconfig --disableldap --disableldapauth --ldapserver=ldaps://$IPSERVER \
		--ldapbasedn="dc=$DC1,dc=$DC2" --disablemkhomedir --enableldaptls --update
		authconfig --enableldap --enableldapauth --ldapserver=ldaps://$IPSERVER \
		--ldapbasedn="dc=$DC1,dc=$DC2" --enablemkhomedir --disableldaptls --update
	else	
		authconfig --disableldap --disableldapauth --ldapserver=ldap://$IPSERVER \
		--ldapbasedn="dc=$DC1,dc=$DC2" --disablemkhomedir --update
		authconfig --enableldap --enableldapauth --ldapserver=ldap://$IPSERVER \
		--ldapbasedn=dc="$DC1,dc=$DC2" --enablemkhomedir --update
	fi
else
	if [[ $CONFIGURETLS == "yes" ]]
	then
		authconfig --disableldap --disableldapauth --ldapserver=ldaps://$IPSERVER \
		--ldapbasedn="dc=$DC1,dc=$DC2" --disablemkhomedir --enableldaptls --update
		authconfig --enableldap --enableldapauth --ldapserver=ldaps://$IPSERVER \
		--ldapbasedn="dc=$DC1,dc=$DC2" --disableldaptls --update
	else
		authconfig --disableldap --disableldapauth --ldapserver=$IPSERVER \
		--ldapbasedn="dc=$DC1,dc=$DC2" --disablemkhomedir --update
		authconfig --enableldap --enableldapauth --ldapserver=$IPSERVER \
		--ldapbasedn="dc=$DC1,dc=$DC2" --update
	fi
fi

if [[ $CONFIGURETLS == "yes" ]] && [[ $SELFSIGNEDCERT == "yes" ]]
then
	# This will disable the certificate validation done by clients as we are
	# using a self signed cert
	echo
	echo "##############################################################"
	echo "Disabling certification validation for self signed certificate"
	sed -i '/tls_reqcert/a tls_reqcert allow' /etc/nslcd.conf
	echo "Done"
	echo "##############################################################"
fi

systemctl restart nslcd

echo
echo "####################################"
echo "OpenLDAP client successfully created"
echo "####################################"

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

