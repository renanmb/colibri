#!/usr/bin/env python3
"""
ASUS ROG Crosshair X870E Glacial USB Port & Controller Live Auditor
Detects which physical controller domain each connected USB device is routed through.
Includes an interactive live-watch mode (--watch) to assist physical port relocation.
"""

import os
import sys
import time
import glob

CONTROLLER_MAP = {
    "0000:7c:00.3": ("CPU-DIRECT On-Die (Ryzen 9 9950X USB 3.2 Gen 2)", "INTERNAL FRONT-PANEL HEADER ONLY (Not on Rear I/O)"),
    "0000:7c:00.4": ("CPU-DIRECT On-Die (Ryzen 9 9950X USB 3.2 Gen 2)", "INTERNAL FRONT-PANEL HEADER ONLY (Not on Rear I/O)"),
    "0000:7d:00.0": ("CPU-DIRECT Legacy (Ryzen 9 9950X USB 2.0)", "INTERNAL PCB HEADER"),
    "0000:79:00.0": ("CPU-DIRECT PCIe 4.0 x4 (ASMedia ASM4242 USB4 40G)", "OPTIMAL: Rear USB4 Type-C (Use USB-C to USB-A Adapter)"),
    "0000:0f:00.0": ("AMD Promontory 21 Chipset 1 (Downstream PCH)", "AVOID FOR 1000Hz MOUSE (Generates Split-Lock IRQs on Monitor Hub)"),
    "0000:11:00.0": ("AMD Promontory 21 Chipset 2 (Downstream PCH)", "GOOD: Isolated from Monitor Hub / LCD (Near 10G LAN Ports)"),
}

def scan_devices():
    devices = {}
    for u in sorted(glob.glob("/sys/bus/usb/devices/[0-9]*-[0-9]*")):
        if ":" in os.path.basename(u):
            continue
        dev_name = os.path.basename(u)
        real_path = os.path.realpath(u)
        parts = real_path.split("/")
        pci_addr = "Unknown"
        for p in parts:
            if p.startswith("0000:"):
                pci_addr = p
                
        speed = "Unknown"
        if os.path.exists(os.path.join(u, "speed")):
            try:
                speed = open(os.path.join(u, "speed")).read().strip() + " Mbps"
            except Exception:
                pass
                
        product = ""
        if os.path.exists(os.path.join(u, "product")):
            try:
                product = open(os.path.join(u, "product")).read().strip()
            except Exception:
                pass
                
        manufacturer = ""
        if os.path.exists(os.path.join(u, "manufacturer")):
            try:
                manufacturer = open(os.path.join(u, "manufacturer")).read().strip()
            except Exception:
                pass

        name = f"{manufacturer} {product}".strip() or "Generic USB Device"
        domain_info, status = CONTROLLER_MAP.get(pci_addr, (f"PCI {pci_addr}", "Unknown Controller"))
        
        devices[dev_name] = {
            "sys_path": dev_name,
            "pci": pci_addr,
            "speed": speed,
            "name": name,
            "domain": domain_info,
            "recommendation": status
        }
    return devices

def print_audit(devices):
    print("=" * 110)
    print(" ASUS ROG CROSSHAIR X870E GLACIAL: LIVE USB TOPOLOGY & CONTROLLER DOMAIN AUDIT")
    print("=" * 110)
    print(f"{'DEV PATH':<10} | {'PCI CONTROLLER':<15} | {'SPEED':<12} | {'DEVICE NAME':<35} | {'DOMAIN / STATUS'}")
    print("-" * 110)
    for dev_name, d in devices.items():
        print(f"{d['sys_path']:<10} | {d['pci']:<15} | {d['speed']:<12} | {d['name'][:34]:<35} | {d['domain']}")
        if "AVOID" in d['recommendation']:
            print(f"           --> WARNING: {d['recommendation']}")
        elif "OPTIMAL" in d['recommendation']:
            print(f"           --> OPTIMAL: {d['recommendation']}")
        elif "GOOD" in d['recommendation']:
            print(f"           --> OK (ISOLATED): {d['recommendation']}")
    print("-" * 110)
    print("CPU-DIRECT / HIGH-PERFORMANCE CONTROLLER STATUS:")
    for c_addr in ["0000:79:00.0", "0000:7c:00.3", "0000:7c:00.4"]:
        active = [d for d in devices.values() if d['pci'] == c_addr]
        domain_name, _ = CONTROLLER_MAP[c_addr]
        if active:
            print(f"  [ACTIVE] {c_addr} ({domain_name}): {len(active)} device(s) connected")
        else:
            print(f"  [EMPTY]  {c_addr} ({domain_name}): 0 devices")
    print("=" * 110)

def watch_live():
    print("=" * 110)
    print(" ASUS ROG CROSSHAIR X870E GLACIAL: INTERACTIVE USB PORT RELOCATION DETECTOR")
    print(" Plug your mouse or keyboard into rear USB ports. Events will appear below in real-time.")
    print(" Press Ctrl+C to exit.")
    print("=" * 110)
    
    prev_devices = scan_devices()
    print_audit(prev_devices)
    print("\n[LISTENING] Ready for USB plug/unplug events...\n")
    
    try:
        while True:
            time.sleep(0.5)
            curr_devices = scan_devices()
            
            # Check for unplugged
            for dev_id, d in prev_devices.items():
                if dev_id not in curr_devices:
                    print(f"[-] [UNPLUGGED] {d['name']} removed from {dev_id} (PCI: {d['pci']})")
                    
            # Check for plugged
            for dev_id, d in curr_devices.items():
                if dev_id not in prev_devices:
                    if d['pci'] == "0000:79:00.0":
                        print(f"[+] [SUCCESS - CPU-DIRECT PCIe VIA USB4!] {d['name']} connected to {dev_id} on {d['pci']} ({d['domain']})")
                        print(f"    --> EXCELLENT! Direct CPU PCIe 4.0 x4 link. Bypasses both Promontory 21 chipsets!\n")
                    elif d['pci'] in ["0000:7c:00.3", "0000:7c:00.4", "0000:7d:00.0"]:
                        print(f"[+] [SUCCESS - CPU-DIRECT ON-DIE!] {d['name']} connected to {dev_id} on {d['pci']} ({d['domain']})")
                        print(f"    --> PERFECT! Native CPU on-die USB controller. Zero chipset contention.\n")
                    elif d['pci'] == "0000:11:00.0":
                        print(f"[+] [VALID - CHIPSET 2 ISOLATION] {d['name']} connected to {dev_id} on {d['pci']} ({d['domain']})")
                        print(f"    --> GOOD: Isolated from Dell monitor hub and LCD on Chipset 1. Suitable zero-cost setup.\n")
                    else:
                        print(f"[!] [CHIPSET 1 PORT] {d['name']} connected to {dev_id} on {d['pci']} ({d['domain']})")
                        print(f"    --> WARNING: Shared with Dell monitor hub and internal LCD (generates split-lock IRQs).\n")
                        
            prev_devices = curr_devices
    except KeyboardInterrupt:
        print("\n[DETECTOR] Exited live listener.")

if __name__ == "__main__":
    if "--watch" in sys.argv:
        watch_live()
    else:
        print_audit(scan_devices())
        print("\nTip: Run 'python3 scripts/detect_usb_controllers.py --watch' while plugging in devices to verify ports in real time.")
