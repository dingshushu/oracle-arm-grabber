# reserve-ip result

- action: apply
- old_ip: 161.118.248.18
- utc: 2026-10-14T23:05:42Z

```
TENANCY: ocid1.tenancy.oc1..aaaaaaaaii4jwevwldqla6tyb2wy3avachyzlhuoizmvg4wrjczdpfe5aznq
ACTION=apply OLD_IP=161.118.248.18 NAME=amd2-reserved
TARGET: 161.118.248.18 lifetime=EPHEMERAL state=ASSIGNED id=ocid1.publicip.oc1.ap-singapore-1.abzwsljrffysupzjmabzwej2du4eomlycefr7f7od7hwvldlybdaazkzoocq priv=ocid1.privateip.oc1.ap-singapore-1.abzwsljr2dqk3y7wnvizpfzt75b3fu2fuzoumwehutmlhmyhmvzozprfvotq
PRE-CREATED reserved: 161.118.224.53 ocid1.publicip.oc1.ap-singapore-1.amaaaaaaxqj7kvqawbqlmthydji53utpjnjyhpg7irge47ak5uevusqor3va AVAILABLE
STEP: deleting ephemeral 161.118.248.18 (id=ocid1.publicip.oc1.ap-singapore-1.abzwsljrffysupzjmabzwej2du4eomlycefr7f7od7hwvldlybdaazkzoocq)
STEP: private ip freed (no public ip)
  poll state: ASSIGNED priv=ocid1.privateip.oc1.ap-singapore-1.abzwsljr2dqk3y7wnvizpfzt75b3fu2fuzoumwehutmlhmyhmvzozprfvotq
NEW_IP: 161.118.224.53
NEW_PUBLIC_IP_OCID: ocid1.publicip.oc1.ap-singapore-1.amaaaaaaxqj7kvqawbqlmthydji53utpjnjyhpg7irge47ak5uevusqor3va
NEW_STATE: ASSIGNED lifetime=RESERVED
RESULT: converted 161.118.248.18 -> 161.118.224.53
```
