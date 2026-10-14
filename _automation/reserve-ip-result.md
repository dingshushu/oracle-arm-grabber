# reserve-ip result

- action: apply
- old_ip: 168.107.86.163
- utc: 2026-10-14T23:07:03Z

```
TENANCY: ocid1.tenancy.oc1..aaaaaaaaii4jwevwldqla6tyb2wy3avachyzlhuoizmvg4wrjczdpfe5aznq
ACTION=apply OLD_IP=168.107.86.163 NAME=amd-reserved
TARGET: 168.107.86.163 lifetime=EPHEMERAL state=ASSIGNED id=ocid1.publicip.oc1.ap-singapore-1.abzwsljrwe3xgq3f2otjex5pwzumcitxj4fkucs4mhl4zlisbdjghsfmuqbq priv=ocid1.privateip.oc1.ap-singapore-1.abzwsljrklfufivtrfmjtawy2rfekoxhmzdedr6ijd75vferkap4ess7f27a
PRE-CREATED reserved: 161.118.219.192 ocid1.publicip.oc1.ap-singapore-1.amaaaaaaxqj7kvqazh35arddaisvfinvpf5ebxj7a4htgsqdpayc7jjxwhrq AVAILABLE
STEP: deleting ephemeral 168.107.86.163 (id=ocid1.publicip.oc1.ap-singapore-1.abzwsljrwe3xgq3f2otjex5pwzumcitxj4fkucs4mhl4zlisbdjghsfmuqbq)
STEP: private ip freed (no public ip)
  poll state: ASSIGNED priv=ocid1.privateip.oc1.ap-singapore-1.abzwsljrklfufivtrfmjtawy2rfekoxhmzdedr6ijd75vferkap4ess7f27a
NEW_IP: 161.118.219.192
NEW_PUBLIC_IP_OCID: ocid1.publicip.oc1.ap-singapore-1.amaaaaaaxqj7kvqazh35arddaisvfinvpf5ebxj7a4htgsqdpayc7jjxwhrq
NEW_STATE: ASSIGNED lifetime=RESERVED
RESULT: converted 168.107.86.163 -> 161.118.219.192
```
