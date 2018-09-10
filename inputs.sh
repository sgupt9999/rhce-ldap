# Common inputs for ldap server and client
IPSERVER=172.31.120.16
HOSTSERVER="garfield99991.mylabserver.com"
IPCLIENT=172.31.114.179
HOSTCLIENT="garfield99994.mylabserver.com"
SCPUSER="user"
HOSTS=/etc/hosts
DC1="mylabserver"
DC2="com"

# New users to create
USER1="user1"
USER2="user2"
USER3="user3"
USERPW1="redhat11"
USERPW2="redhat22"
USERPW3="redhat33"

# All TLS options
CONFIGURETLS="yes"
SELFSIGNEDCERT="yes"
NEWROOT="yes" # Configure a new root authority to be able to sign certificates
NEWROOTCLIENT="yes" # This option to install root CA on client is currently not working. Still investigating

# All automount options
AUTOMOUNT="yes" # If want to automount the home directories
NFSHOSTEDHOMEDIR="yes" # The server hosts the home directory
NFSHOMEDIR="/nfs-share1"

