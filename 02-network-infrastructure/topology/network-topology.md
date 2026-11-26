# Network Topology

| Field | Value |
|---|---|
| Document ID | NET-REF-001 |
| Owner | IT Specialist |
| Status | Approved – v1.1 (Milestone 4) |
| Last reviewed | 2026-11-26 |
| Related requirements | BR-05, BR-09, BR-15, BR-19, BR-25 |

## 1. Logical topology

```mermaid
flowchart TB
    ISP["ISP fibre<br/>203.0.113.10/29"]
    LTE["4G/5G modem<br/>failover"]
    FW["TC-FW01 firewall<br/>router-on-a-stick, VPN, DHCP for all VLANs<br/>gateways 10.10.x.1"]
    SW["TC-SW01 48-port PoE+ switch<br/>10.10.10.2"]
    VPN(["Remote staff<br/>VPN 10.10.60.0/24"])

    ISP -->|WAN1| FW
    LTE -->|WAN2| FW
    VPN -.->|encrypted tunnel| FW
    FW ==>|"port 41 – trunk VLAN 10,20,30,40,50"| SW

    subgraph V10["VLAN 10 – MGMT 10.10.10.0/24"]
        AP["TC-AP01..03<br/>.11–.13"]
        UPS["TC-UPS01 .5"]
        ILO["TC-HV01 iDRAC .20"]
    end

    subgraph V30["VLAN 30 – SERVERS 10.10.30.0/24"]
        HV["TC-HV01 Hyper-V host .10"]
        DC1["TC-DC01 .11<br/>AD DS / DNS"]
        DC2["TC-DC02 .12<br/>AD DS / DNS"]
        FS["TC-FS01 .20<br/>File / DFS-N"]
        NAS["TC-NAS01 .30<br/>Backups"]
        HV --- DC1
        HV --- DC2
        HV --- FS
    end

    subgraph V20["VLAN 20 – STAFF 10.10.20.0/24"]
        LT["20 laptops via docks<br/>D-01..D-24"]
        MR["Meeting rooms<br/>TC-MR-001/002"]
        WIFI20["SSID TechCorp"]
    end

    subgraph V40["VLAN 40 – PRINTERS 10.10.40.0/24"]
        PRN["TC-PRN01 .10<br/>TC-PRN02 .11"]
    end

    subgraph V50["VLAN 50 – GUEST 10.10.50.0/24"]
        WIFI50["SSID TechCorp-Guest<br/>internet only"]
    end

    SW --- V10
    SW --- V30
    SW --- V20
    SW --- V40
    AP -.->|tagged 20| WIFI20
    AP -.->|tagged 50| WIFI50

    M365[("Microsoft 365 / Entra ID")]
    DC1 -.->|Entra Connect sync| M365
    NAS -.->|offsite copy| CLOUD[("Cloud backup storage")]
```

## 2. Physical topology

```mermaid
flowchart LR
    subgraph RACK["Comms room – 18U rack (on TC-UPS01)"]
        ONT["ISP ONT"] --> FW["TC-FW01"]
        LTE["4G/5G modem"] --> FW
        FW -->|red, port 41| SW["TC-SW01"]
        SW -->|black, 42–43 SET team| HV["TC-HV01"]
        SW -->|grey, 44| ILO["iDRAC"]
        SW -->|black, 45–46 LACP| NAS["TC-NAS01"]
        SW -->|grey, 47| UPS["TC-UPS01"]
        SW --- PP1["Patch panel PP1<br/>D-01..D-24"]
        SW --- PP2["Patch panel PP2<br/>D-25..D-44"]
    end
    PP1 -->|Cat6| DESKS["24 desks → docks"]
    PP2 -->|Cat6| MRS["Meeting rooms D-25..28"]
    PP2 -->|Cat6 PoE+| APS["3 ceiling APs D-29..31"]
    PP2 -->|Cat6| PRNS["Printers D-32..33"]
```

## 3. Why this design

| Choice | Reason |
|---|---|
| Single switch, star topology | 33 active drops fit on one 48-port switch; no inter-switch links to troubleshoot |
| Firewall routes between VLANs (router-on-a-stick) | Every inter-VLAN flow passes a stateful firewall rule – meets BR-15 without a layer-3 switch |
| 1 Gbps trunk to firewall | Most traffic is to the internet (M365) or within VLAN 20/30 on the switch; upgrade path: 10G SFP+ if the trunk exceeds 60 % utilisation |
| Wi-Fi on the same VLANs as wired | Staff get identical access wired or wireless; guests are separated by VLAN, not only by SSID |
| Dual WAN | ISP outage fails over to 4G/5G automatically (BR-25) |

## 4. Lab equivalent

The lab PC runs **Windows 11 Home**, which has no Hyper-V, so the lab uses
**Oracle VirtualBox** plus **Cisco Packet Tracer**. The full build is in
[lab-environment.md](lab-environment.md).

| Production | Lab |
|---|---|
| TC-FW01 | pfSense CE VM: WAN = VirtualBox NAT, one NIC per VLAN on internal networks `tc-vlan10` … `tc-vlan50` |
| TC-SW01 + VLANs | VirtualBox internal networks act as access-port VLANs; the switch CLI (VLANs, trunks, hardening) is built in Packet Tracer |
| Wi-Fi APs | Documented only – SSID-to-VLAN mapping simulated by attaching a VM to `tc-vlan20` or `tc-vlan50` |
| TC-HV01 | The lab PC itself (VirtualBox host) |
| Laptops / guests | Windows 11 or lightweight Linux VMs on `tc-vlan20` / `tc-vlan50` |
