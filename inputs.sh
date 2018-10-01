# Common inputs for ldap server and client
IPSERVER=172.31.125.183
HOSTSERVER="garfield99991.mylabserver.com"
IPCLIENT=172.31.111.30
HOSTCLIENT="garfield99992.mylabserver.com"
SCPUSER="user" # username used to copy new root certificate from server to client
HOSTS=/etc/hosts
DC1="mylabserver"
DC2="com"

# Kerberos options
KERBEROSAUTH="yes" # Use kerberos instead of LDAP for authentication
LDAPPASSWORD="yes" # Only have Kerberos password for ssh logins
REALM="MYLABSERVER.COM"
DOMAIN="mylabserver.com"
IPKDC=172.31.125.183
HOSTKDC="garfield99991.mylabserver.com"
SERVICES=(host)
SERVERKEYTABFILE="/etc/krb5.keytab"
CLIENTKEYTABFILE="/tmp/1.keytab"

# New users to create
USER1="user1"
USER2="user2"
USER3="user3"
LDAPUSERPW1="redhat11"
LDAPUSERPW2="redhat22"
LDAPUSERPW3="redhat33"
KERBEROSUSERPW1="redhat111"
KERBEROSUSERPW2="redhat222"
KERBEROSUSERPW3="redhat333"

# All TLS options
CONFIGURETLS="yes"
#NEWROOT="no" # Using a self-signed certificate
NEWROOT="yes" # Configure a new root authority to be able to sign certificates
ADMINEMAIL="admin@mylabserver.com"
ORGANIZATION="New Root Agency" # This and email information needs to be added to the root certificate, otherwise client doesnt recognise

# All automount options
AUTOMOUNT="yes" # If want to automount the home directories
NFSHOSTEDHOMEDIR="yes" # The server hosts the home directory
NFSHOMEDIR="/nfs-share103" # User home directory if being mounted from server

