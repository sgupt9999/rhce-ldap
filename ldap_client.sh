#!/bin/bash
########################################################################################
# This script will configure openldap client on Centos/RHEL 7 with diff security options
# Can use self-signed server certficate and connect on ldaps
# or can use new root certificate and connect on ldap
########################################################################################
# Start of user inputs
########################################################################################

ENABLEHOMEDIR="yes"
#ENABLEHOMEDIR="no"

# the following options if automounting home directories
AUTOMASTERFILE="/etc/auto.master"
AUTOFSTIMEOUT=60
AUTOMAPFILE="/etc/auto.map"

# Kerberos options
KRBCONFFILE="/etc/krb5.conf"
KRBCONFBKFILE="/etc/krb5_backup.conf"

########################################################################################
# End of user inputs
########################################################################################


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
INSTALLPACKAGES3="krb5-workstation pam_krb5"

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
		if [[ $NEWROOT == "no" ]]
		then
			# using self signed certificate. Connect on ldaps
			authconfig --enableldap --enableldapauth --ldapserver=ldaps://$HOSTSERVER \
			--ldapbasedn="dc=$DC1,dc=$DC2" --enablemkhomedir --disableldaptls --update
		else
			# using a new root certificate. Connect on ldap and enable TLS
			authconfig --enableldap --enableldapauth --ldapserver=ldap://$HOSTSERVER \
			--ldapbasedn="dc=$DC1,dc=$DC2" --enablemkhomedir --enableldaptls --update
		fi
	else
		# No certificates. Connect on ldap
		authconfig --enableldap --enableldapauth --ldapserver=ldap://$HOSTSERVER \
		--ldapbasedn="dc=$DC1,dc=$DC2" --enablemkhomedir --update
	fi
else
	if [[ $CONFIGURETLS == "yes" ]]
	then
		if [[ $NEWROOT == "no" ]]
		then
			# using self signed certificate. Connect on ldaps
			authconfig --enableldap --enableldapauth --ldapserver=ldaps://$HOSTSERVER \
			--ldapbasedn="dc=$DC1,dc=$DC2" --disableldaptls --update
		else
			# using a new root certificate. Connect on ldap and enable TLS
			authconfig --enableldap --enableldapauth --ldapserver=ldap://$HOSTSERVER \
			--ldapbasedn="dc=$DC1,dc=$DC2" --enableldaptls --update
		fi
	else
		# No certificates. Connect on ldap
		authconfig --enableldap --enableldapauth --ldapserver=ldap://$HOSTSERVER \
		--ldapbasedn="dc=$DC1,dc=$DC2" --update
	fi
fi

if [[ $CONFIGURETLS == "yes" ]]
then
	if [[ $NEWROOT == "yes" ]]
	then
		# Copy the new root CA from the server
		echo 
		echo "###############################################################################"
		echo "Installing the new root CA certficate on this machine. Need to copy from server"
		rm -rf /etc/openldap/cacerts/rootca.*
		scp $SCPUSER@$IPSERVER:/tmp/rootca.crt /etc/openldap/cacerts/rootca.pem
		chmod 644 /etc/openldap/cacerts/rootca.pem
		restorecon /etc/openldap/cacerts/rootca.pem
		authconfig --disableldapauth --update
		authconfig --enableldapauth --update
		echo "Done"
		echo "###############################################################################"
	else
		# This will disable the certificate validation done by clients as we are
		# using a self signed cert
		echo
		echo "##############################################################"
		echo "Disabling certification validation for self signed certificate"
		sed -i '/tls_reqcert/a tls_reqcert allow' /etc/nslcd.conf
		echo "Done"
		echo "##############################################################"
	fi
fi

if [[ $NFSHOSTEDHOMEDIR == "yes" && $AUTOMOUNT == "yes" ]]
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
		yum -y remove autofs -q > /dev/null 2>&1
		rm -rf $AUTOMAPFILE
		rm -rf $AUTOMASTERFILE
		echo "Done"
		echo "###########################"
	fi

	echo
	echo "##########################"
	echo "Installing $INSTALLPACKAGES2"
	yum -y install $INSTALLPACKAGES2 -q > /dev/null 2>&1
	echo "Done"
	echo "##########################"

	rm -rf $NFSHOMEDIR	
	mkdir $NFSHOMEDIR
	chmod 755 $NFSHOMEDIR

	sed -i "/misc/a $NFSHOMEDIR $AUTOMAPFILE --timeout=$AUTOFSTIMEOUT" $AUTOMASTERFILE
	echo "* -fstype=auto $IPSERVER:$NFSHOMEDIR/&" > $AUTOMAPFILE


	systemctl start autofs
	systemctl -q enable autofs
	systemctl restart nslcd
fi


if [[ $KERBEROSAUTH == "yes" ]]
then
        ###############################################################################
        # This is the section for Kerberos installation. Use kerberos instead of LDAP
        ###############################################################################

	authconfig --disableldapauth --update # disable LDAP auth

        sed -i "s/.*$HOSTKDC/#&/g" $HOSTS
        echo "$IPKDC $HOSTKDC" >> $HOSTS

	echo
	echo "###################################################"
	echo "Installing $INSTALLPACKAGES3"
	yum install -y -q $INSTALLPACKAGES3 > /dev/null 2>&1
	echo "Done"	
	echo "###################################################"

	# This file is installed by krb5-libs which comes pre-installed. Make a backup if one doesnt already
	# exist
	if [ -f $KRBCONFBKFILE ]
	then
		cp -f $KRBCONFBKFILE $KRBCONFFILE
	else
		cp -f $KRBCONFFILE $KRBCONFBKFILE
	fi


	sed -i "s/#//g" $KRBCONFFILE
	sed -i "s/EXAMPLE.COM/$REALM/g" $KRBCONFFILE
	sed -i "s/kerberos.example.com/$HOSTKDC/g" $KRBCONFFILE
	sed -i "s/example.com/$DOMAIN/g" $KRBCONFFILE

        # Copy the key tab file from the server
        echo 
        echo "####################################################################"
        echo "Installing the kerberos client keytab file. Need to copy from server"
	echo
	sleep 2
	rm -rf /etc/krb5.keytab
        scp $SCPUSER@$IPKDC:$CLIENTKEYTABFILE /etc/krb5.keytab
        chmod  0600 /etc/krb5.keytab
        echo "Done"
        echo "####################################################################"


	# Adding kerberos to PAM
	authconfig --enablekrb5 --update

	# Adding kerberos to ssh client
	sed -i 's/.*GSSAPIAuthentication.*/GSSAPIAuthentication yes/g' /etc/ssh/ssh_config
	sed -i 's/.*GSSAPIDelegateCredentials.*/GSSAPIDelegateCredentials yes/g' /etc/ssh/ssh_config

	# Adding kerberos for sshing into the server
	# Changes to allow Kerberos password for ssh login
        echo "KerberosAuthentication yes" >> /etc/ssh/sshd_config
        echo "KerberosOrLocalPasswd yes" >> /etc/ssh/sshd_config
        echo "KerberosTicketCleanup yes" >> /etc/ssh/sshd_config
        echo "KerberosGetAFSToken yes" >> /etc/ssh/sshd_config
        echo "KerberosUseKuserok yes" >> /etc/ssh/sshd_config

	systemctl reload sshd
else
	authconfig --disablekrb5 --update
fi

systemctl restart nslcd

echo
echo "##################################################################"
echo "OpenLDAP client successfully created with the following properties"
echo
#authconfig --test | egrep 'nss_ldap|pam_ldap|pam_krb5|homedir|legacy|LDAP server'
echo -n "LDAP Server: "
echo `authconfig --test | grep "LDAP server" | head -n 1 | awk -F " = " '{print $2}'`
echo -n "LDAP user lookup: "
echo `authconfig --test | grep nss_ldap| awk '{print $3}'`
echo -n "LDAP Authentication: "
echo `authconfig --test | grep pam_ldap| awk '{print $3}'`
echo -n "KERBEROS Authentication: "
echo `authconfig --test | grep pam_krb5| awk '{print $3}'`
echo -n "LDAP SSH login allowed: "
echo `if [[ $LDAPPASSWORD != "no" ]]; then echo "enabled"; else echo "disabled"; fi`
echo -n "Home Directory Creation: "
echo `authconfig --test | grep homedir| awk '{print $5}'`
echo -n "NFS hosted home directory: "
echo `if [[ $NFSHOSTEDHOMEDIR == "yes" ]]; then echo "enabled"; else echo "disabled"; fi`
echo -n "Automount: "
echo `if [[ $AUTOMOUNT == "yes" ]]; then echo "enabled"; else echo "disabled"; fi`
echo -n "Use legacy services (instead of SSSD): "
echo `authconfig --test | grep legacy| awk '{print $10}'`
echo
echo "################################################################"
