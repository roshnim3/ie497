#!/usr/bin/env python3
"""Decode tx_packets.csv produced by the tick-to-trade firmware.

Each row is a captured 64-byte frame. We parse Ethernet / IPv4 / UDP /
OUCH layers and assert the fixed-by-spec fields. Tokens, quantity, and
price are extracted from the OUCH body (network byte order).

Usage:
    python3 script/decode_tick_to_trade.py sim/vcs/tx_packets.csv
"""

import csv
import sys

# Constants the firmware hard-codes into every emitted frame.
EXPECTED_DST_MAC   = bytes([0x02, 0x00, 0x00, 0x00, 0x00, 0x01])
EXPECTED_SRC_MAC   = bytes([0x02, 0x00, 0x00, 0x00, 0x00, 0x02])
EXPECTED_ETHERTYPE = 0x0800
EXPECTED_IP_VER_IHL = 0x45
EXPECTED_IP_DSCP   = 0x00
EXPECTED_IP_TOTLEN = 50
EXPECTED_IP_TTL    = 64
EXPECTED_IP_PROTO  = 17
EXPECTED_IP_SRC    = bytes([10, 0, 0, 2])
EXPECTED_IP_DST    = bytes([10, 0, 0, 1])
EXPECTED_UDP_SRC   = 0xABCD
EXPECTED_UDP_DST   = 0x1234
EXPECTED_UDP_LEN   = 30
EXPECTED_OUCH_MSG  = ord('O')
EXPECTED_OUCH_SIDE = ord('B')
EXPECTED_OUCH_TIF  = ord('I')
EXPECTED_OUCH_DISP = ord('Y')


def parse_frame(bytes_hex: str) -> dict:
    bs = bytes.fromhex(bytes_hex)
    out = {"length": len(bs)}
    if len(bs) != 64:
        out["valid_length"] = False
        return out
    out["valid_length"] = True

    # Ethernet header (14B).
    eth_dst = bs[0:6]
    eth_src = bs[6:12]
    eth_type = int.from_bytes(bs[12:14], "big")
    out["eth_dst"] = eth_dst.hex(":")
    out["eth_src"] = eth_src.hex(":")
    out["ethertype"] = eth_type
    out["valid_ethernet"] = (
        eth_dst == EXPECTED_DST_MAC
        and eth_src == EXPECTED_SRC_MAC
        and eth_type == EXPECTED_ETHERTYPE
    )

    # IPv4 header (20B).
    ip_ver_ihl = bs[14]
    ip_dscp    = bs[15]
    ip_totlen  = int.from_bytes(bs[16:18], "big")
    ip_id      = int.from_bytes(bs[18:20], "big")
    ip_ff      = int.from_bytes(bs[20:22], "big")
    ip_ttl     = bs[22]
    ip_proto   = bs[23]
    ip_chk     = int.from_bytes(bs[24:26], "big")
    ip_src     = bs[26:30]
    ip_dst     = bs[30:34]
    out["ip_proto"] = ip_proto
    out["ip_src"]   = ".".join(str(b) for b in ip_src)
    out["ip_dst"]   = ".".join(str(b) for b in ip_dst)
    out["valid_ipv4"] = (
        ip_ver_ihl == EXPECTED_IP_VER_IHL
        and ip_dscp    == EXPECTED_IP_DSCP
        and ip_totlen  == EXPECTED_IP_TOTLEN
        and ip_ttl     == EXPECTED_IP_TTL
        and ip_proto   == EXPECTED_IP_PROTO
        and ip_src     == EXPECTED_IP_SRC
        and ip_dst     == EXPECTED_IP_DST
    )

    # UDP header (8B).
    udp_src = int.from_bytes(bs[34:36], "big")
    udp_dst = int.from_bytes(bs[36:38], "big")
    udp_len = int.from_bytes(bs[38:40], "big")
    udp_chk = int.from_bytes(bs[40:42], "big")
    out["udp_src"] = udp_src
    out["udp_dst"] = udp_dst
    out["udp_len"] = udp_len
    out["valid_udp"] = (
        udp_src == EXPECTED_UDP_SRC
        and udp_dst == EXPECTED_UDP_DST
        and udp_len == EXPECTED_UDP_LEN
    )

    # OUCH body (22B at offset 42).
    ouch_msg    = bs[42]
    ouch_side   = bs[43]
    ouch_token  = int.from_bytes(bs[44:48], "big")
    ouch_qty    = int.from_bytes(bs[48:52], "big")
    ouch_price  = int.from_bytes(bs[52:56], "big")
    ouch_locate = int.from_bytes(bs[56:58], "big")
    ouch_tif    = bs[58]
    ouch_disp   = bs[59]
    out["ouch_msg"]   = chr(ouch_msg)
    out["ouch_side"]  = chr(ouch_side)
    out["ouch_token"] = ouch_token
    out["ouch_qty"]   = ouch_qty
    out["ouch_price"] = ouch_price
    out["valid_ouch"] = (
        ouch_msg  == EXPECTED_OUCH_MSG
        and ouch_side == EXPECTED_OUCH_SIDE
        and ouch_tif  == EXPECTED_OUCH_TIF
        and ouch_disp == EXPECTED_OUCH_DISP
    )

    return out


# Parser ROM (mirrors hvl/common/fake_packet_parser.sv). The order token
# in each accepted frame is the parser's seq number; the parser starts at
# seq=2 (seq=1 is the preloaded packet which the firmware drops) and
# emits in rom_idx = (seq-2) mod 8. So we can recover the expected
# shares/price from the order token without trusting the firmware.
PARSER_ROM = [
    # rom_idx: (msg_type, shares, price)
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


def expected_for_token(token: int):
    """Returns (expected_qty, expected_price) for a given OUCH order
    token (= parser seq). The firmware emits one frame iff the parser
    packet at seq passed the decision predicate; return None if the
    seq's ROM entry would have been rejected."""
    if token < 2:
        return None
    rom_idx = (token - 2) & 0x7
    mtype, qty, price = PARSER_ROM[rom_idx]
    accept = mtype == 0x41 and price > THRESHOLD_PRICE and qty >= MIN_SHARES
    return (qty, price) if accept else None


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <tx_packets.csv>", file=sys.stderr)
        return 2

    path = sys.argv[1]
    with open(path) as f:
        rows = list(csv.DictReader(f))

    n = len(rows)
    print(f"Frames in {path}: {n}")
    if n == 0:
        return 1

    header = "{:>4} {:>6} {:>6} {:>8} {:>4} {:>4} {:>5} {:>5} {:>5} {:>5} {:>9}".format(
        "idx", "token", "qty", "price", "msg", "side", "eth", "ipv4", "udp", "ouch", "match"
    )
    print(header)
    print("-" * len(header))

    all_struct_valid = True
    all_match        = True
    mismatch_rows    = []

    for i, row in enumerate(rows):
        f = parse_frame(row["bytes_hex"])
        ve = f.get("valid_ethernet", False)
        vi = f.get("valid_ipv4",     False)
        vu = f.get("valid_udp",      False)
        vo = f.get("valid_ouch",     False)
        token = f.get("ouch_token", -1)
        qty   = f.get("ouch_qty",   -1)
        price = f.get("ouch_price", -1)

        struct_ok = ve and vi and vu and vo
        all_struct_valid &= struct_ok

        # Cross-check qty/price against the parser ROM via order token.
        exp = expected_for_token(token)
        if exp is None:
            match_str = "no-rom"
            all_match = False
            mismatch_rows.append((i, token, qty, price, "token has no accepted ROM entry"))
        elif (qty, price) == exp:
            match_str = "OK"
        else:
            match_str = "MISMATCH"
            all_match = False
            mismatch_rows.append(
                (i, token, qty, price, f"expected qty={exp[0]} price={exp[1]}")
            )

        print(
            "{:>4} {:>6} {:>6} {:>8} {:>4} {:>4} {:>5} {:>5} {:>5} {:>5} {:>9}".format(
                i, token, qty, price,
                f.get("ouch_msg", "?"),
                f.get("ouch_side", "?"),
                "Y" if ve else "N",
                "Y" if vi else "N",
                "Y" if vu else "N",
                "Y" if vo else "N",
                match_str,
            )
        )

    print()
    print(f"frames structurally valid: {all_struct_valid}")
    print(f"qty/price match parser:    {all_match}")
    if mismatch_rows:
        print(f"\n{len(mismatch_rows)} mismatch row(s):")
        for r in mismatch_rows[:20]:
            print(f"  idx={r[0]} token={r[1]} qty={r[2]} price={r[3]}  ({r[4]})")

    return 0 if (all_struct_valid and all_match) else 1


if __name__ == "__main__":
    sys.exit(main())
