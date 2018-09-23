# Common inputs for ldap server and client
IPSERVER=172.31.17.81
HOSTSERVER="server.mylabserver.com"
IPCLIENT=172.31.107.58
HOSTCLIENT="client.mylabserver.com"
SCPUSER="user" # username used to copy new root certificate from server to client
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
#NEWROOT="no" # Using a self-signed certificate
NEWROOT="yes" # Configure a new root authority to be able to sign certificates
ADMINEMAIL="admin@mylabserver.com"
ORGANIZATION="New Root Agency" # This and email information needs to be added to the root certificate, otherwise client doesnt recognise

# All automount options
AUTOMOUNT="yes" # If want to automount the home directories
NFSHOSTEDHOMEDIR="yes" # The server hosts the home directory
NFSHOMEDIR="/nfs-share100" # User home directory if being mounted from server

