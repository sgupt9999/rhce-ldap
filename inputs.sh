#!/bin/bash
# Common inputs for ldap server and client
IPSERVER=172.31.30.135
HOSTSERVER="server.myserver.com"
IPCLIENT=172.31.30.26
HOSTCLIENT="client.myserver.com"
HOSTS=/etc/hosts
DC1="myserver"
DC2="com"
USER1="user1"
USER2="user2"
USER3="user3"
USERPW1="redhat11"
USERPW2="redhat22"
USERPW3="redhat33"
CONFIGURETLS="no"
SELFSIGNEDCERT="yes"
NFSHOSTEDHOMEDIR="yes" # The server hosts the home directory
#NFSHOSTEDHOMEDIR="no"
NFSHOMEDIR="/nfs-dirshare"
AUTOMOUNT="yes" # If want to automount the home directories
#AUTOMOUNT="no"

