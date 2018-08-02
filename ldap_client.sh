#!/bin/bash
# This script will configure openldap client on Centos/RHEL 7 with diff security options
####################################################################################
# Start of user inputs
####################################################################################

ENABLEHOMEDIR="yes"
#ENABLEHOMEDIR="no"

# the following options if automounting home directories
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
INSTALLPACKAGES2="autofs"

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

if [[ $NFSHOSTEDHOMEDIR="yes" && $AUTOMOUNT="yes" ]]
then
	if yum list installed autofs > /dev/null 2>&1
	then
		systemctl -q is-active autofs && {
		systemctl stop autofs
		systemctl -q disable autofs
		}

		echo
		echo "###########################"
		echo "Removing old copy of autofs"
		yum -y remove autofs -q > /dev/null
		rm -rf /etc/auto.master
		rm -rf /etc/auto.map
		echo "Done"
		echo "###########################"
	fi

	echo
	echo "##########################"
	echo "Installing $INSTALLPACKAGES2"
	yum -y install $INSTALLPACKAGES2 -q > /dev/null
	echo "Done"
	echo "##########################"
	
	if ! [[ -d $NFSHOMEDIR ]]
	then
		# make the mount directory only if ir doesnt already exist
		mkdir $NFSHOMEDIR
		chmod 755 $NFSHOMEDIR
	fi

	#echo "$NFSHOMEDIR $AUTOMAPFILE --timeout=$AUTOFSTIMEOUT" > $AUTOMASTERFILE
	sed -i "/misc/a $NFSHOMEDIR $AUTOMAPFILE --timeout=$AUTOFSTIMEOUT" $AUTOMASTERFILE
	echo "* -fstype=auto $IPSERVER:/$NFSHOMEDIR/&" > $AUTOMAPFILE


	systemctl start autofs
	systemctl -q enable autofs
	systemctl restart nslcd
fi


echo
echo "####################################"
echo "OpenLDAP client successfully created"
echo "####################################"
