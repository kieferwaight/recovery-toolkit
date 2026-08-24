# Luks Layout
This toolkit will provide the ability to setup custom luks layouts. Some will be general patterns for all machines and others will be unique aspects for specific machines, such as specific cypthers for machines that cant handle standard encryption (MacMini 4,1).

Since a lot of disks start unencrypted, we should perform a secure erase within reason based
on the disk type we are targeting to install a ubuntu server node to.

We are going to use xfs since its ideal for docker and database environments

Backups of headers should be stored on this recovery usb.
Backups of the decryption key should be stored on this recovery usb
Lean towards generated keys with good entropy. Generating and storing this on
this USB is ideal since the USB is encrypted and we can achieve a zero cleartext 
key strategy. 

link to 
[Hdd Secure Erase](./hdd-secure-erase.md)
[SSD Secure Erase](./ssd-secure-erase.md)
[nvme Secure Erase](./nvme-secure-erase.md)