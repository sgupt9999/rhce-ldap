
RHCE ldap setup files for server and client
------------------------------------------------

Options
-------
- Configure TLS
- Self signed certificates
- NFS mount share for home directories
- Automount
- Sample users
- Can use usemigrationtools or a custom script
- Firewalld update

inputs
--------
- Input file has common inputs for server and client

ldap_server.sh
--------------
- password for ldap Manager
- usemigrationtools or custom script
- testing changes on the server
- firewalld change

ldap_client.sh
--------------
- enable home directories
- enable automount
