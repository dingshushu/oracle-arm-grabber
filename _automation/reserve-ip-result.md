# reserve-ip result

- action: plan
- old_ip: 
- utc: 2026-10-14T23:00:53Z

```
TENANCY: ocid1.tenancy.oc1..aaaaaaaaii4jwevwldqla6tyb2wy3avachyzlhuoizmvg4wrjczdpfe5aznq
ACTION=plan OLD_IP=- NAME=reserved-ip
INSTANCES: 2
--- amd | RUNNING | ocid1.instance.oc1.ap-singapore-1.anzwsljrxqj7kvqcjmaxxcchlvrmqtmd7d7xotkdnkbefdafsmzsrdjtvuja
Traceback (most recent call last):
  File "<stdin>", line 43, in <module>
AttributeError: 'ComputeClient' object has no attribute 'list_vnics'
```
