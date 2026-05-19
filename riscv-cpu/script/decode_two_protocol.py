#!/usr/bin/env python3
"""Decode tx_packets.csv produced by itch_two_protocol.c.

Dispatch on the Ethernet ethertype field (bytes 12-13):
    0x0806 -> ARP request — validate HTYPE/PTYPE/HLEN/PLEN/OPER, extract
              sender/target HW + IP addresses.
    0x0800 -> IPv4 / UDP / OUCH order frame — same path as
              decode_tick_to_trade.py.
    other  -> UNKNOWN, treated as failure.

Usage:
    python3 script/decode_two_protocol.py sim/vcs/tx_packets.csv
"""

import csv
import sys

EXPECTED_SRC_MAC = bytes([0x02, 0x00, 0x00, 0x00, 0x00, 0x02])
ARP_BROADCAST    = bytes([0xFF] * 6)

# OUCH-side expected constants (mirror decode_tick_to_trade.py).
EXPECTED_OUCH_DST_MAC = bytes([0x02, 0x00, 0x00, 0x00, 0x00, 0x01])
EXPECTED_OUCH_ETHTYPE = 0x0800
EXPECTED_IP_VER_IHL   = 0x45
EXPECTED_IP_TOTLEN    = 50
EXPECTED_IP_TTL       = 64
EXPECTED_IP_PROTO     = 17
EXPECTED_IP_SRC       = bytes([10, 0, 0, 2])
EXPECTED_IP_DST       = bytes([10, 0, 0, 1])
EXPECTED_UDP_SRC      = 0xABCD
EXPECTED_UDP_DST      = 0x1234
EXPECTED_UDP_LEN      = 30

PARSER_ROM = [
    (0x41, 1000, 100000),
    (0x41,  500, 200000),
    (0x41, 2000,  99000),
    (0x44,  300,  80000),
    (0x41, 1500, 120000),
    (0x41, 2500,  95000),
    (0x41,  800, 110000),
    (0x41, 1200, 105000),
]
THRESHOLD_PRICE = 99000
MIN_SHARES      = 800


def expected_qty_price(token: int):
    if token < 2:
        return None
    rom_idx = (token - 2) & 0x7
    mtype, qty, price = PARSER_ROM[rom_idx]
    if mtype == 0x41 and price > THRESHOLD_PRICE and qty >= MIN_SHARES:
        return (qty, price)
    return None


def fmt_mac(b):
    return ":".join(f"{x:02x}" for x in b)


def fmt_ip(b):
    return ".".join(str(x) for x in b)


def parse_arp(bs):
    """Parse 64-byte ARP frame, return (valid, details, info dict)."""
    if len(bs) != 64:
        return False, f"length {len(bs)} != 64", {}

    eth_dst = bs[0:6]
    eth_src = bs[6:12]
    htype = int.from_bytes(bs[14:16], "big")
    ptype = int.from_bytes(bs[16:18], "big")
    hlen  = bs[18]
    plen  = bs[19]
    oper  = int.from_bytes(bs[20:22], "big")
    sha   = bs[22:28]
    spa   = bs[28:32]
    tha   = bs[32:38]
    tpa   = bs[38:42]

    ok = (eth_dst == ARP_BROADCAST
          and eth_src == EXPECTED_SRC_MAC
          and htype == 0x0001
          and ptype == 0x0800
          and hlen  == 6
          and plen  == 4
          and oper  == 0x0001
          and sha   == EXPECTED_SRC_MAC
          and spa   == EXPECTED_IP_SRC
          and tpa   == EXPECTED_IP_DST)

    info = {
        "eth_dst": fmt_mac(eth_dst), "eth_src": fmt_mac(eth_src),
        "htype": htype, "ptype": ptype, "hlen": hlen, "plen": plen, "oper": oper,
        "sha": fmt_mac(sha), "spa": fmt_ip(spa),
        "tha": fmt_mac(tha), "tpa": fmt_ip(tpa),
    }
    details = (f"req who-has {fmt_ip(tpa)} tell {fmt_ip(spa)}"
               if oper == 0x0001
               else f"reply {fmt_mac(sha)} is at {fmt_ip(spa)}")
    return ok, details, info


def parse_ouch(bs):
    """Parse 64-byte IPv4/UDP/OUCH frame; mirror decode_tick_to_trade.py."""
    if len(bs) != 64:
        return False, f"length {len(bs)} != 64", {}

    eth_dst = bs[0:6]
    eth_src = bs[6:12]
    ip_ver  = bs[14]
    ip_len  = int.from_bytes(bs[16:18], "big")
    ip_ttl  = bs[22]
    ip_pro  = bs[23]
    ip_src  = bs[26:30]
    ip_dst  = bs[30:34]
    udp_src = int.from_bytes(bs[34:36], "big")
    udp_dst = int.from_bytes(bs[36:38], "big")
    udp_len = int.from_bytes(bs[38:40], "big")
    msg     = bs[42]
    side    = bs[43]
    token   = int.from_bytes(bs[44:48], "big")
    qty     = int.from_bytes(bs[48:52], "big")
    price   = int.from_bytes(bs[52:56], "big")
    tif     = bs[58]
    disp    = bs[59]

    ok = (eth_dst == EXPECTED_OUCH_DST_MAC
          and eth_src == EXPECTED_SRC_MAC
          and ip_ver  == EXPECTED_IP_VER_IHL
          and ip_len  == EXPECTED_IP_TOTLEN
          and ip_ttl  == EXPECTED_IP_TTL
          and ip_pro  == EXPECTED_IP_PROTO
          and ip_src  == EXPECTED_IP_SRC
          and ip_dst  == EXPECTED_IP_DST
          and udp_src == EXPECTED_UDP_SRC
          and udp_dst == EXPECTED_UDP_DST
          and udp_len == EXPECTED_UDP_LEN
          and msg     == ord('O')
          and side    == ord('B')
          and tif     == ord('I')
          and disp    == ord('Y'))

    expected = expected_qty_price(token)
    if expected is not None and (qty, price) != expected:
        ok = False

    info = {
        "token": token, "qty": qty, "price": price,
        "msg": chr(msg), "side": chr(side),
        "ip_proto": ip_pro,
        "ip_src": fmt_ip(ip_src), "ip_dst": fmt_ip(ip_dst),
        "udp_src": udp_src, "udp_dst": udp_dst,
    }
    details = f"token={token} qty={qty} px={price} {chr(side)}"
    return ok, details, info


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <tx_packets.csv>", file=sys.stderr)
        return 2

    with open(sys.argv[1]) as f:
        rows = list(csv.DictReader(f))

    print(f"Frames in {sys.argv[1]}: {len(rows)}\n")
    header = "{:>4} {:>6} {:<8} {:<6} details".format("idx", "len", "proto", "valid")
    print(header)
    print("-" * (len(header) + 50))

    proto_counts = {"ARP": 0, "OUCH": 0, "UNKNOWN": 0}
    all_ok = True

    for i, row in enumerate(rows):
        bs   = bytes.fromhex(row["bytes_hex"])
        length = int(row["length"])
        if len(bs) < 14:
            proto = "UNKNOWN"
            ok = False
            details = f"frame too short (len={length})"
        else:
            ethertype = int.from_bytes(bs[12:14], "big")
            if ethertype == 0x0806:
                proto = "ARP"
                ok, details, _ = parse_arp(bs)
            elif ethertype == 0x0800:
                proto = "OUCH"
                ok, details, _ = parse_ouch(bs)
            else:
                proto = "UNKNOWN"
                ok = False
                details = f"unexpected ethertype 0x{ethertype:04x}"

        proto_counts[proto] += 1
        if not ok:
            all_ok = False

        print("{:>4} {:>6d} {:<8} {:<6} {}".format(
            i, length, proto, ("Y" if ok else "N"), details
        ))

    print()
    print(f"counts:   ARP={proto_counts['ARP']}  OUCH={proto_counts['OUCH']}  UNKNOWN={proto_counts['UNKNOWN']}")
    print(f"all frames valid: {all_ok}")
    return 0 if all_ok and proto_counts["UNKNOWN"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
