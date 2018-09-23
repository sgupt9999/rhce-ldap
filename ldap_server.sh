#!/bin/bash
####################################################################################
# This script will configure openldap server on Centos and RHEL 7
# The hostname should be defined as per DC1 and DC2 in the inputs file
####################################################################################
# Start of user inputs
####################################################################################
PASSWORD="redhat"

# Use migration tools file or a custom script to add users to LDAP database
USEMIGRATIONTOOLS="no"
#USEMIGRATIONTOOLS="yes"

# Check if the user and group information was successfully added to the LDAP DB
#DBTESTING="yes"
DBTESTING="no"

# Firewalld shoud be installed and running before any changes added for LDAP
FIREWALL="yes"
#FIREWALL="no"
####################################################################################
# End of user inputs
####################################################################################


if (( $EUID != 0 )); then
	echo
	echo "##########################################################"
	echo "ERROR: You need to have root privileges to run this script"
	echo "##########################################################"
	exit 1
else
	echo
	echo "########################################################"
	echo "This script will install openldap server on this machine"
	echo "########################################################"
	sleep 5
fi

source ./inputs.sh
INSTALLPACKAGES="openldap-servers openldap-clients migrationtools"
INSTALLPACKAGES2="nfs-utils"
INSTALLPACKAGES3="rpcbind"

# Add server and client to /etc/hosts file
sed -i "s/.*$IPSERVER.*/#&/g" $HOSTS
sed -i "s/.*$IPCLIENT.*/#&/g" $HOSTS
echo "$IPSERVER $HOSTSERVER" >> $HOSTS
echo "$IPCLIENT $HOSTCLIENT" >> $HOSTS

if yum list installed openldap-servers > /dev/null 2>&1
then
	systemctl -q is-active slapd && {
		systemctl stop slapd
		systemctl -q disable slapd
	}
	echo 
	echo "#################"
	echo "Removing packages"
	yum remove -y -q $INSTALLPACKAGES > /dev/null 2>&1
	rm -rf /etc/openldap/slapd.d/
	rm -rf /etc/openldap/password
	rm -rf /var/lib/ldap/
	rm -rf /root/base.ldif
	echo "Done"
	echo "#################"
	sleep 2
fi

echo
echo "###########################################################"
echo "Installing $INSTALLPACKAGES"
yum install -y -q $INSTALLPACKAGES > /dev/null 2>&1
echo "Done"
echo "###########################################################"
sleep 2

systemctl start slapd
systemctl -q enable slapd

# Prepare the LDAP database
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown ldap:ldap /var/lib/ldap/*

# Generate hashed LDAP password
slappasswd -s $PASSWORD -n > /etc/openldap/password

# Edit the database files
ldapmodify -Q -Y EXTERNAL -H ldapi:/// << EOF > /dev/null
dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=$DC1,dc=$DC2
EOF

ldapmodify -Q -Y EXTERNAL -H ldapi:/// << EOF > /dev/null
dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=Manager,dc=$DC1,dc=$DC2
EOF

ldapmodify -Q -Y EXTERNAL -H ldapi:/// << EOF > /dev/null
dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcRootPW
olcRootPW: $(</etc/openldap/password)
EOF

ldapmodify -Q -Y EXTERNAL -H ldapi:/// << EOF > /dev/null
dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base="cn=Manager,dc=$DC1,dc=$DC2" read by * none
EOF


if [[ $CONFIGURETLS == "yes" ]]
then
	if [[ $NEWROOT == "yes" ]]
	then
		# Create a new root signing authority
		echo
		echo "#################################################"
		echo "Installing a new root CA and a signed certificate"

		rm -rf /etc/openldap/certs/rootca.*
		rm -rf /etc/openldap/certs/$DC1.*

		openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out /etc/openldap/certs/rootca.key
		chmod 0600 /etc/openldap/certs/rootca.key
		openssl req -x509 -days 365 -new -key /etc/openldap/certs/rootca.key -subj  "/CN=$HOSTSERVER/O=$ORGANIZATION/emailAddress=$ADMINEMAIL" -set_serial 100 -out /etc/openldap/certs/rootca.crt # Creating a new root cert

		openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out /etc/openldap/certs/$DC1.key
		chmod 0600 /etc/openldap/certs/$DC1.key
		openssl req -new -key /etc/openldap/certs/$DC1.key -subj "/CN=$HOSTSERVER/emailAddress=$ADMINEMAIL" -out /etc/openldap/certs/$DC1.csr
		openssl x509 -req -days 365 -set_serial 101 -CA /etc/openldap/certs/rootca.crt -CAkey /etc/openldap/certs/rootca.key -in /etc/openldap/certs/$DC1.csr -out /etc/openldap/certs/$DC1.crt
	else
		# Create a self-signed certificate
		echo
		echo "####################################"
		echo "Installing a self signed certificate"
		rm -rf /etc/openldap/certs/$DC1.*
		# Generate a self-signed certificate and a private key
		openssl req -x509 -days 365 -newkey rsa:2048 -nodes \
		-keyout /etc/openldap/certs/$DC1.key \
		-out /etc/openldap/certs/$DC1.crt \
		-subj '/CN=$HOSTSERVER/emailAddress=$ADMINEMAIL' 

	fi

	chown -R ldap:ldap /etc/openldap/certs/*
	rm -rf ./cert1.ldif

	# It seems both the key and the cert have to be part of the same command, otherwise LDAP gives an error
	# IF run as separate commands then somehow even when the first command errors out, it keeps the info
	# in memory so the 2nd command can run successfully. After that the 1st command can be run again
	
	if [[ $NEWROOT == "yes" ]]
	then
		# Extra section if also created a new root signing authority
		echo "dn: cn=config" >> ./cert1.ldif
		echo "changetype: modify" >> ./cert1.ldif
		echo "add: olcTLSCACertificateFile" >> ./cert1.ldif
		echo "olcTLSCACertificateFile: /etc/openldap/certs/rootca.crt" >> ./cert1.ldif
		echo "-" >> ./cert1.ldif
		echo "replace: olcTLSCertificateFile" >> ./cert1.ldif
		echo "olcTLSCertificateFile: /etc/openldap/certs/$DC1.crt" >> ./cert1.ldif
		echo "-" >> ./cert1.ldif
		echo "replace: olcTLSCertificateKeyFile" >> ./cert1.ldif
		echo "olcTLSCertificateKeyFile: /etc/openldap/certs/$DC1.key" >> ./cert1.ldif
	else
		echo "dn: cn=config" >> ./cert1.ldif
		echo "changetype: modify" >> ./cert1.ldif
		echo "replace: olcTLSCertificateFile" >> ./cert1.ldif
		echo "olcTLSCertificateFile: /etc/openldap/certs/$DC1.crt" >> ./cert1.ldif
		echo "-" >> ./cert1.ldif
		echo "replace: olcTLSCertificateKeyFile" >> ./cert1.ldif
		echo "olcTLSCertificateKeyFile: /etc/openldap/certs/$DC1.key" >> ./cert1.ldif
	fi

	ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f ./cert1.ldif

	sed -i 's@^SLAPD_URLS.*@SLAPD_URLS="ldapi:/// ldap:/// ldaps:///"@' /etc/sysconfig/slapd
	echo "Done"
	echo "####################################"

	if [[ $NEWROOT == "yes" ]]
	then
		# Install the new root on the client machine
		# Copy the root certificate to /tmp so can be copied by the client
		rm -rf /tmp/rootca.crt
		cp /etc/openldap/certs/rootca.crt /tmp/
		chmod 777 /tmp/rootca.crt
	fi
	
fi

# Add minimum schemas
ldapadd -Q -Y EXTERNAL -H ldapi:// -f /etc/openldap/schema/cosine.ldif > /dev/null
ldapadd -Q -Y EXTERNAL -H ldapi:// -f /etc/openldap/schema/nis.ldif > /dev/null
ldapadd -Q -Y EXTERNAL -H ldapi:// -f /etc/openldap/schema/inetorgperson.ldif > /dev/null


# Create base LDIF
cat > /root/base.ldif << EOF
dn: dc=$DC1,dc=$DC2
objectClass: top
objectClass: dcObject
objectClass: organization
o: $DC1 $DC2
dc: $DC1

dn: cn=Manager,dc=$DC1,dc=$DC2
objectClass: organizationalRole
cn: Manager
description: Directory Manager

dn: ou=People,dc=$DC1,dc=$DC2
objectClass: organizationalUnit
ou: People

dn: ou=Group,dc=$DC1,dc=$DC2
objectClass: organizationalUnit
ou: Group
EOF

ldapadd -x -w $PASSWORD -D "cn=Manager,dc=$DC1,dc=$DC2" -f /root/base.ldif > /dev/null

systemctl restart slapd

# Create new local users
userdel -rf $USER1 > /dev/null 2>&1
userdel -rf $USER2 > /dev/null 2>&1
userdel -rf $USER3 > /dev/null 2>&1

if [[ $NFSHOSTEDHOMEDIR == "yes" ]]
then
	
	rm -rf $NFSHOMEDIR
	mkdir $NFSHOMEDIR
	useradd -d $NFSHOMEDIR/$USER1 $USER1
	useradd -d $NFSHOMEDIR/$USER2 $USER2
	useradd -d $NFSHOMEDIR/$USER3 $USER3
else
	useradd $USER1  > /dev/null
	useradd $USER2  > /dev/null
	useradd $USER3  > /dev/null
fi

echo $USERPW1 | passwd --stdin $USER1 > /dev/null
echo $USERPW2 | passwd --stdin $USER2 > /dev/null
echo $USERPW3 | passwd --stdin $USER3 > /dev/null

# Only moving all users with uid >= 1000
grep "10[0-9][0-9]" /etc/passwd | sudo tee /root/passwd > /dev/null
grep "10[0-9][0-9]" /etc/group  | sudo tee /root/group > /dev/null

if [[ $USEMIGRATIONTOOLS == "yes" ]]
then
	# Make the changes the in the migration tools file
	sed -i "0,/.*DEFAULT_MAIL_DOMAIN/s/.*DEFAULT_MAIL_DOMAIN.*/\$DEFAULT_MAIL_DOMAIN = \"$DC1.$DC2\";/" /usr/share/migrationtools/migrate_common.ph
	sed -i "0,/.*DEFAULT_BASE/s/.*DEFAULT_BASE.*/\$DEFAULT_BASE = \"dc=$DC1,dc=$DC2\";/" /usr/share/migrationtools/migrate_common.ph
	sed -i "0,/.*EXTENDED_SCHEMA/s/.*EXTENDED_SCHEMA.*/\$EXTENDED_SCHEMA = 1;/" /usr/share/migrationtools/migrate_common.ph
	/usr/share/migrationtools/migrate_passwd.pl /root/passwd /root/users.ldif
	/usr/share/migrationtools/migrate_group.pl /root/group /root/groups.ldif
else
	G_LDIF="/root/groups.ldif"
	rm -rf $G_LDIF
	IFS=":"
	while read -r G_NAME G_PASSWD G_ID G_USERS; do
		echo "dn: cn=$G_NAME,ou=Group,dc=$DC1,dc=$DC2" >> $G_LDIF
		echo "objectClass: posixGroup" >> $G_LDIF
		echo "objectClass: top" >> $G_LDIF
		echo "cn: $G_NAME" >> $G_LDIF
		echo "userPassword: {crypt}$G_PASSWD" >> $G_LDIF
		echo "gidNumber: $G_ID" >> $G_LDIF
		echo >> $G_LDIF
	done < /root/group

	U_LDIF="/root/users.ldif"
	rm -rf $U_LDIF
	while read -r U_NAME U_PASSWD U_ID G_ID U_DESC U_HOME U_SHELL; do
        	U_PASSWD_A=(`grep ^${U_NAME}: /etc/shadow`)
		U_SHADOW_PASSWD=${U_PASSWD_A[1]}
        	U_SHADOW_CHANGE=${U_PASSWD_A[2]}
        	U_SHADOW_MIN=${U_PASSWD_A[3]}
        	U_SHADOW_MAX=${U_PASSWD_A[4]}
        	U_SHADOW_WARNING=${U_PASSWD_A[5]}

        	echo "dn: uid=$U_NAME,ou=People,dc=$DC1,dc=$DC2" >> $U_LDIF
        	echo "uid: $U_NAME" >> $U_LDIF
        	echo "cn: $U_NAME" >> $U_LDIF
        	echo "sn: $U_NAME" >> $U_LDIF
        	echo "mail: $U_NAME@$DC1.$DC2" >> $U_LDIF
        	echo "objectClass: person" >> $U_LDIF
        	echo "objectClass: organizationalPerson" >> $U_LDIF
        	echo "objectClass: inetOrgPerson" >> $U_LDIF
        	echo "objectClass: posixAccount" >> $U_LDIF
        	echo "objectClass: top" >> $U_LDIF
        	echo "objectClass: shadowAccount" >> $U_LDIF
        	echo "userPassword: {crypt}$U_SHADOW_PASSWD" >> $U_LDIF
		if [[ $U_SHADOW_CHANGE ]]
		then
		# For users where the password is the same as the time 
		# of creating the VM, this gives a blank
        		#echo "this is the value of shadow change $U_SHADOW_CHANGE"
			echo "shadowLastChange: $U_SHADOW_CHANGE" >> $U_LDIF
		fi
        	echo "shadowMin: $U_SHADOW_MIN" >> $U_LDIF
        	if [[ $U_SHADOW_MAX ]]
		then
			# On Linux academy servers this is coming as blank for USER user
			# and giving an error when adding to LDAP db
			# If blank then make it 99999
			
			echo "shadowMax: $U_SHADOW_MAX" >> $U_LDIF
		else
			echo "shadowMax: 99999" >> $U_LDIF
		fi
			
        	echo "shadowWarning: $U_SHADOW_WARNING" >> $U_LDIF
        	echo "loginShell: $U_SHELL" >> $U_LDIF
        	echo "uidNumber: $U_ID" >> $U_LDIF
        	echo "gidNumber: $G_ID" >> $U_LDIF
        	echo "homeDirectory: $U_HOME" >> $U_LDIF
		if [[ $U_DESC ]]
		then
			echo "gecos: $U_DESC" >> $U_LDIF
		fi
        	echo >> $U_LDIF
	done < /root/passwd
fi

# Add base config, suers and groups to LDAP DB
ldapadd -x -w $PASSWORD -D "cn=Manager,dc=$DC1,dc=$DC2" -f /root/users.ldif > /dev/null
ldapadd -x -w $PASSWORD -D "cn=Manager,dc=$DC1,dc=$DC2" -f /root/groups.ldif > /dev/null

# This section configures NFs server on this machine if required
if [[ $NFSHOSTEDHOMEDIR == "yes" ]]
then
	if yum list installed nfs-utils > /dev/null 2>&1
	then
		systemctl -q is-active nfs && {
		systemctl -q stop nfs
		systemctl -q disable nfs
		}
	
		echo 
		echo "##############################"
		echo "Removing old copy of nfs-utils"
		yum remove -y nfs-utils -q > /dev/null 2>&1
		rm -rf /etc/exports
		sleep 3
		echo "Done"
		echo "##############################"
	fi

	echo
	echo "############################"
	echo "Installing $INSTALLPACKAGES2 $INSTALLPACKAGES3"
	yum install -y $INSTALLPACKAGES2 -q > /dev/null 2>&1
	yum install -y $INSTALLPACKAGES3 -q > /dev/null 2>&1
	echo "Done"
	echo "############################"

	echo "$NFSHOMEDIR $IPCLIENT(rw,root_squash)" >> /etc/exports
	exportfs -avr > /dev/null

	systemctl start nfs
	systemctl start rpcbind
	systemctl -q enable nfs
	systemctl -q enable rpcbind

fi


if [[ $FIREWALL == "yes" ]]
then
	if systemctl -q is-active firewalld
	then
		if [[ $CONFIGURETLS == "yes"  && $NEWROOT == "no" ]]
		then
			# Add ldaps for self signed certifcates
			echo
			echo "#############################################"
			echo "Adding ldaps to the firewall allowed services"
			firewall-cmd -q --permanent --remove-service ldap
			firewall-cmd -q --permanent --remove-service ldaps
			firewall-cmd -q --permanent --add-service ldaps
			firewall-cmd -q --reload
			echo "Done"
			echo "#############################################"
		else
			# Add ldap for new root certificate or no TLS
			echo
			echo "############################################"
			echo "Adding ldap to the firewall allowed services"
			firewall-cmd -q --permanent --remove-service ldap
			firewall-cmd -q --permanent --remove-service ldaps
			firewall-cmd -q --permanent --add-service ldap
			firewall-cmd -q --reload
			echo "Done"
			echo "############################################"
		fi
		if [[ $NFSHOSTEDHOMEDIR == "yes" ]]
		then
			echo
			echo "###########################################"
			echo "Adding nfs to the firewall allowed services"
			firewall-cmd -q --permanent --add-service nfs
			firewall-cmd -q --reload
			echo "Done"
			echo "###########################################"
		fi
	else
		echo
		echo "####################################################"
		echo "Firewalld is not active. No changes made to firewall"
		echo "####################################################"
	fi
fi


if [[ $DBTESTING  == "yes" ]]
then
	echo "############################################################"
	echo "Testing if the entries were added to the LDAP DB correctly"
	echo "############################################################"
	echo
	echo
	echo "Checking for user $USER1......."
	echo
	sleep 5
	ldapsearch -x cn=$USER1 -b dc=$DC1,dc=$DC2
	echo "############################################################"
	sleep 5
	echo
	echo "Checking for user $USER2......."
	echo
	sleep 5
	ldapsearch -x cn=$USER2 -b dc=$DC1,dc=$DC2
	echo "############################################################"
	sleep 5
	echo
	echo "Checking for the group information for user $USER1......."
	echo
	sleep 5
	ldapsearch -x cn=$USER1 -b ou=Group,dc=$DC1,dc=$DC2
	echo "############################################################"
	sleep 5
	echo
	echo "Checking for all groups................................."
	echo
	sleep 5
	ldapsearch -x objectClass=top -b ou=Group,dc=$DC1,dc=$DC2
	echo "############################################################"
fi

systemctl restart slapd

echo
echo "####################################"
echo "OpenLDAP server successfully created"
echo "####################################"
