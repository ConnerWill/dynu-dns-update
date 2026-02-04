# dynu-dns-update

A bash script to automatically update your
[Dynu](https://www.dynu.com) Dynamic DNS hostname with your current public IP.
Supports IPv4 and optionally IPv6.
Designed to run safely from cron with state tracking.

## Table of Contents

<!--toc:start-->
- [dynu-dns-update](#dynu-dns-update)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [Setup](#setup)
    - [Installation](#installation)
      - [Install Script](#install-script)
      - [Manual installation](#manual-installation)
    - [Cron Setup](#cron-setup)
  - [Links](#links)
<!--toc:end-->

## Features

- Updates IPv4 and IPv6 addresses *(skips IPv6 if unavailable)*
- Avoids conflicts with environment variables *(`DYNU_*` prefix)*
- Cron-friendly with lockfile to prevent overlapping runs
- Stores last known IP in a separate state file for comparison

## Setup

### Installation

#### Install Script

Run the `install.sh` script

```bash
./install.sh
```

#### Manual installation

Place the script in a location accessible to the user running cron. Common options

- `/usr/local/bin/dynu-ddns-update.sh` *(system-wide)*
- `~/bin/dynu-ddns-update.sh` *(user-specific)*

```bash
sudo install -vDm755 "dynu-ddns-update.sh" "/usr/local/bin/dynu-ddns-update.sh"
```

Run once manually to generate the configuration file

```bash
/usr/local/bin/dynu-ddns-update.sh
```

This will create a configuration file at `~/.config/dynu-ddns-update/dynu_ddns.conf`

Edit the configuration file

```conf
DYNU_USERNAME="your_username_here"
DYNU_PASSWORD="your_password_here"
DYNU_HOSTNAME="example.dynu.com"   # or comma-separated for multiple hostnames
USE_SSL=true                        # true or false
STATE_FILE="/var/tmp/dynu_ddns_state"
```

### Cron Setup

Open your crontab for editing

```bash
crontab -e
```

Add the following line to run the updater every 10 minutes

```console
*/10 * * * * /usr/local/bin/dynu_ddns.sh
```

Add the following line to run the updater every 10 minutes and log output

```console
*/10 * * * * /usr/local/bin/dynu_ddns.sh >> /var/log/dynu_ddns.log 2>&1
```

> [!NOTE]
> If you are not root, choose a log file under your home directory,
> e.g. `~/dynu_ddns.log`. Make sure the path is writable.

Optional: Use `logrotate` to prevent logs from growing indefinitely

```console
/var/log/dynu_ddns.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    create 644 root root
}
```

## Links

- [Dynu IP Update Protocol docs](https://www.dynu.com/DynamicDNS/IP-Update-Protocol)


