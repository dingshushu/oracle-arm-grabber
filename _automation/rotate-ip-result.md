# rotate-ip result

- action: rotate
- instance: 新加坡E2
- utc: 2026-10-28T15:35:46Z

```
instance: amd-2            RUNNING    VM.Standard.E2.1.Micro ocid1.instance.oc1.ap-singapore-1.anzwsljrxqj7kvqcsmcdrnem5wkhcr2pr34ez27mux7u2vc4pjxfr3injvea
instance: 新加坡E2            RUNNING    VM.Standard.E2.1.Micro ocid1.instance.oc1.ap-singapore-1.anzwsljrxqj7kvqcjmaxxcchlvrmqtmd7d7xotkdnkbefdafsmzsrdjtvuja
TARGET INSTANCE: 新加坡E2  ocid1.instance.oc1.ap-singapore-1.anzwsljrxqj7kvqcjmaxxcchlvrmqtmd7d7xotkdnkbefdafsmzsrdjtvuja
vnic nic_index=0 private=10.0.0.207 public=161.118.219.192 id=ocid1.vnic.oc1.ap-singapore-1.abzwsljri66jxgf7xocooye3c5udfujxrhwx2tjitixhcfaf2lp6a5e3k6qa
private ip 10.0.0.207 primary=True id=ocid1.privateip.oc1.ap-singapore-1.abzwsljrklfufivtrfmjtawy2rfekoxhmzdedr6ijd75vferkap4ess7f27a
CURRENT PUBLIC IP: ip=161.118.219.192 lifetime=RESERVED state=ASSIGNED id=ocid1.publicip.oc1.ap-singapore-1.amaaaaaaxqj7kvqazh35arddaisvfinvpf5ebxj7a4htgsqdpayc7jjxwhrq
STEP: release old public ip 161.118.219.192 (ocid1.publicip.oc1.ap-singapore-1.amaaaaaaxqj7kvqazh35arddaisvfinvpf5ebxj7a4htgsqdpayc7jjxwhrq, lifetime=RESERVED)
  released (404)
  old ip released: True
NEW RESERVED: ip=129.221.158.18 lifetime=RESERVED state=AVAILABLE id=ocid1.publicip.oc1.ap-singapore-1.amaaaaaaxqj7kvqaxbozmyjw5tlyuybvatxvb35shvm4cn42xqtjjr7c5bea
  assign request sent (attempt 1)
  state=ASSIGNED priv=ocid1.privateip.oc1.ap-singapore-1.abzwsljrklfufivtrfmjtawy2rfekoxhmzdedr6ijd75vferkap4ess7f27a
OLD_IP: 161.118.219.192
NEW_IP: 129.221.158.18
NEW_PUBLIC_IP_OCID: ocid1.publicip.oc1.ap-singapore-1.amaaaaaaxqj7kvqaxbozmyjw5tlyuybvatxvb35shvm4cn42xqtjjr7c5bea
VERDICT: 161.118.219.192 -> 129.221.158.18
```
