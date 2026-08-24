# Recovery Toolkit

After a fresh install of ubuntu on a portable usb, you can install the toolkit with
```
curl github.com/kieferwaight/recovery-toolkit/ ... bootstrap.sh | sh
```

This sets up the bare minimum to load the repo and handoff to Makefile


data is gitignored, we should setup a pattern for auditability in logging for
historical actions applied on a machine, key generation, luks keys, etc
Figure out a plan for how to organize luks keys, header backups, the disk ID's, etc.

the .env can just be a cp of .env.example, most configs can probably be defaulted