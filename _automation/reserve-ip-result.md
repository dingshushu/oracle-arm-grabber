# reserve-ip result

- action: plan
- old_ip: 
- utc: 2026-10-14T23:04:31Z

```
TENANCY: ocid1.tenancy.oc1..aaaaaaaaii4jwevwldqla6tyb2wy3avachyzlhuoizmvg4wrjczdpfe5aznq
ACTION=plan OLD_IP=- NAME=reserved-ip
INSTANCES: 2
--- amd | RUNNING | ocid1.instance.oc1.ap-singapore-1.anzwsljrxqj7kvqcjmaxxcchlvrmqtmd7d7xotkdnkbefdafsmzsrdjtvuja
  VNIC ocid1.vnic.oc1.ap-singapore-1.abzwsljri66jxgf7xocooye3c5udfujxrhwx2tjitixhcfaf2lp6a5e3k6qa (nic_index=0)
   priv ocid1.privateip.oc1.ap-singapore-1.abzwsljrklfufivtrfmjtawy2rfekoxhmzdedr6ijd75vferkap4ess7f27a primary=True ip=10.0.0.207
    pub-by-priv -> 168.107.86.163 lifetime=EPHEMERAL state=ASSIGNED id=ocid1.publicip.oc1.ap-singapore-1.abzwsljrwe3xgq3f2otjex5pwzumcitxj4fkucs4mhl4zlisbdjghsfmuqbq priv=ocid1.privateip.oc1.ap-singapore-1.abzwsljrklfufivtrfmjtawy2rfekoxhmzdedr6ijd75vferkap4ess7f27a
--- amd-2 | RUNNING | ocid1.instance.oc1.ap-singapore-1.anzwsljrxqj7kvqcsmcdrnem5wkhcr2pr34ez27mux7u2vc4pjxfr3injvea
  VNIC ocid1.vnic.oc1.ap-singapore-1.abzwsljrbqnldylrhv55wf3a6zdqqxhz3y624x32zjuo2eulwgfbqnydf62q (nic_index=0)
   priv ocid1.privateip.oc1.ap-singapore-1.abzwsljr2dqk3y7wnvizpfzt75b3fu2fuzoumwehutmlhmyhmvzozprfvotq primary=True ip=10.0.0.142
    pub-by-priv -> 161.118.248.18 lifetime=EPHEMERAL state=ASSIGNED id=ocid1.publicip.oc1.ap-singapore-1.abzwsljrffysupzjmabzwej2du4eomlycefr7f7od7hwvldlybdaazkzoocq priv=ocid1.privateip.oc1.ap-singapore-1.abzwsljr2dqk3y7wnvizpfzt75b3fu2fuzoumwehutmlhmyhmvzozprfvotq
LOOKUP 168.107.86.163 -> 168.107.86.163 lifetime=EPHEMERAL state=ASSIGNED id=ocid1.publicip.oc1.ap-singapore-1.abzwsljrwe3xgq3f2otjex5pwzumcitxj4fkucs4mhl4zlisbdjghsfmuqbq priv=ocid1.privateip.oc1.ap-singapore-1.abzwsljrklfufivtrfmjtawy2rfekoxhmzdedr6ijd75vferkap4ess7f27a
LOOKUP 161.118.248.18 -> 161.118.248.18 lifetime=EPHEMERAL state=ASSIGNED id=ocid1.publicip.oc1.ap-singapore-1.abzwsljrffysupzjmabzwej2du4eomlycefr7f7od7hwvldlybdaazkzoocq priv=ocid1.privateip.oc1.ap-singapore-1.abzwsljr2dqk3y7wnvizpfzt75b3fu2fuzoumwehutmlhmyhmvzozprfvotq
```
