# Reidentify

**Runtime Network Identity Randomizer for Linux**

Reidentify is an interactive Bash utility that allows you to modify and manage network-facing device identifiers at runtime.

By randomizing identifiers commonly used by networks and services, Reidentify can make a system appear as a different device without permanently modifying the operating system. All changes are session-based and can be reverted at any time.

---

## Features

### MAC Address Randomization

- Fully random MAC generation
    
- Vendor-specific OUI spoofing
    
- Presets for:
    
    - Apple
        
    - iPhone
        
    - Samsung
        
    - Google
        
    - Dell
        
    - Lenovo
        
    - Intel
        
    - Raspberry Pi
        

### Hostname Randomization

- Generates randomized device names
    
- Updates system hostname
    
- Automatically patches `/etc/hosts`
    
- Supports clean restoration
    

### DHCP Fingerprint Spoofing

- Windows 10 profile
    
- macOS profile
    
- Linux profile
    
- Android profile
    
- iOS profile
    
- Randomized client identifiers
    

### TTL / Hop Limit Management

- Modify IPv4 TTL
    
- Modify IPv6 Hop Limit
    
- Common presets:
    
    - Linux / Android (64)
        
    - Windows (128)
        
    - Router-like (255)
        

### IP Renewal

Automatically requests a fresh DHCP lease using:

- NetworkManager
    
- systemd-networkd
    
- dhclient
    
- dhcpcd
    

### Session Logging

Tracks actions and changes throughout the current session.

### One-Command Randomization

Run all identity modification steps in sequence:

```bash
run
```

### Revert Support

Restore:

- Original hostname
    
- Original MAC address
    
- Original TTL values
    
- Original hosts file configuration
    

---

## What Reidentify Does

Reidentify changes several identifiers commonly used to recognize devices on local networks, including:

- MAC address
    
- Hostname
    
- DHCP fingerprint
    
- DHCP client identifier
    
- IPv4 TTL
    
- IPv6 Hop Limit
    
- DHCP lease information
    

This creates a fresh network identity profile and can cause many networks and services to treat the system as a different device.

---

## What Reidentify Does NOT Do

Reidentify is not an anonymity tool.

It does **not** hide:

- Hardware serial numbers
    
- BIOS/UEFI identifiers
    
- TPM identifiers
    
- Browser fingerprints
    
- User accounts
    
- Cookies
    
- ISP information
    
- VPN status
    
- Application-level tracking
    

Network administrators and advanced monitoring systems may still be able to identify a device through other means.

---

## Installation

Clone the repository:

```bash
git clone https://github.com/yourusername/reidentify.git
cd reidentify
```

Make the script executable:

```bash
chmod +x reidentify.sh
```

Run:

```bash
./reidentify.sh
```

---

## Commands

|Command|Description|
|---|---|
|iface|Select network interface|
|mac|Randomize MAC address|
|hostname|Randomize hostname|
|ttl|Modify IPv4/IPv6 TTL|
|ip|Renew DHCP lease|
|dhcp|Spoof DHCP fingerprint|
|run|Execute all randomization steps|
|status|Display current identifiers|
|revert|Restore original values|
|log|Show session activity|
|help|Display command help|
|exit|Exit Reidentify|

---

## Example

```text
reidentify> iface wlan0
reidentify> run

[✓] MAC randomized
[✓] Hostname randomized
[✓] TTL updated
[✓] DHCP fingerprint spoofed
[✓] New DHCP lease obtained
```

---

## Requirements

## Platform Support

### Currently Supported

- Debian 12
- Debian-based distributions that provide compatible networking utilities

Examples:
- Ubuntu
- Linux Mint
- Pop!_OS
- Raspberry Pi OS

### Not Yet Supported

Support for the following distributions is planned but not currently tested:

- Arch Linux
- Fedora
- RHEL / Rocky Linux / AlmaLinux
- openSUSE
- Alpine Linux
- Windows 10/11

Behavior on unsupported distributions is not guaranteed.

Required utilities:

```text
ip
sysctl
hostname
```

Optional utilities:

```text
NetworkManager
dhclient
dhcpcd
systemd-networkd
```

---

## Disclaimer

This software is intended for network testing, privacy research, development, and educational purposes.

Users are responsible for complying with all applicable laws, regulations, network policies, and terms of service.

---

## License

Licensed under the MIT License.
