# StorageP2P

A package to create P2P-connections over a shared storage (i.e. a cloud storage or an IMAP account). The access patterns are designed
in a way that there are basically no requirements for the underlying storage except for being readable/writeable and reliable.


## Storage Requirements
The underlying storage must meet the following requirements:
 - Support for `list`, `read`, `write` and `delete` operations
 - Support for Base64Urlsafe entry names with less than 100 bytes
 - The storage must be reliable and an operation must either succeed or fail without side-effects (i.e. by supporting or simulating atomic
   writes)

That's it :D – in particular there is no need for locking or synchronisation primitives due to a clear ownership model.
