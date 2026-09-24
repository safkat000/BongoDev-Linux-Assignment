# Linux Assignment

This is my submission for the Linux Deep Dive DevOps Practical Lab. The assignment walks through building a small fake service on a real server: give it an identity, give it storage, break it on purpose to see how it fails, lock down access to it, teach it to watch itself, and then tear the whole thing down without leaving anything behind.

Everything below was run on an actual AWS EC2 instance, not a local VM, so a few of the notes are about things that only show up once you are on a real cloud box instead of a laptop.

## What is in here

```
LinuxAssignment/
├── README.md
├── Observation.md
├── Screenshots/
└── Scripts/
```

Screenshots holds the evidence for each step, Scripts holds the actual shell scripts that were used to build and tear down the environment. Observation.md has the longer write up of what happened and what I would change if this were a real server instead of a lab.

## Environment

- Platform: AWS EC2
- OS: Ubuntu Server 26.04 LTS
- Service account name: bgdsvc_safkat
- Shell for the account: /usr/sbin/nologin
- Scratch storage: tmpfs, capped at 256M
- SSH key type: Ed25519
- Monitoring: a small bash script on a 5 minute cron
- Log rotation: logrotate, daily, keep 5

## Walkthrough

**Identity.** The service account was created with `useradd -r -m -s /usr/sbin/nologin`, so it has a home directory and can own files and run processes, but nobody can log into it directly. Script: `01_create_user.sh`.

**Storage.** A 256M tmpfs was mounted at `/mnt/bgdsvc_safkat_tmp` and handed over to the service account. The size cap matters here, since tmpfs lives in RAM and will happily eat all of it if you forget the limit. Script: `02_setup_tmpfs.sh`.

**Breaking it on purpose.** This part filled the tmpfs with `dd`, then ran CPU and memory stress with `stress-ng`, then did all three at once while watching `free -h`, `top`, and `dmesg` from a second terminal. The first attempt at the CPU test actually failed, with `stress-ng` complaining the temp path was not writable, because it was running as the service account from a home directory that account cannot touch. Pointing `stress-ng` at the tmpfs directory instead fixed it. `dmesg` also refused to run without sudo on this particular EC2 image, which was not something I expected going in. No OOM kill happened during the combined test, which is in the screenshots as an empty result rather than something missing. Script: `03_stress_and_populate.sh`.

**SSH access.** An Ed25519 key was generated just for this account and dropped into its `authorized_keys`. Connecting with the key worked, key exchange and authentication both succeeded, but the session ended right after login with a message that the account is not available for interactive use. That is expected, since the account has no real shell. It still proves the key based auth path works, which is the actual point of this part. Script: `ssh_access.sh`.

**SSH hardening.** sshd was reconfigured to listen on 2222, block root login, block password login, and only allow this one account in. Before touching the config, port 2222 was opened in the EC2 security group and port 22 was left alone as a fallback, in case something went wrong. Something did go wrong, just not the thing I expected. After the restart, sshd still only listened on port 22 even though the config file clearly said 2222. It turned out Ubuntu was using systemd socket activation for ssh, and the socket unit was still bound to the old port regardless of what sshd_config said. Turning that socket off and letting the ssh service bind its own port directly fixed it. Script: `harden_ssh.sh`.

**Watching itself.** A monitor script logs memory, tmpfs usage, and the account's running processes every 5 minutes through cron. A second script clears out anything left in the tmpfs older than a day, scheduled for 2am. The monitor script was tested by hand first, then confirmed to actually be firing on its own by watching two separate timestamped entries land in the log five minutes apart without me touching anything. Scripts: `bgdsvc_safkat_monitor.sh`, `bgdsvc_safkat_cleanup_old_files.sh`.

**Keeping logs in check.** logrotate was set up for the monitor log, daily, keeping 5 rotations, compressed, with new files created at 0640 owned by the service account. A forced rotation produced a fresh empty log and a compressed `.1.gz` file with the right owner and permissions, which is what the config asked for.

**Tearing it down.** Cleanup runs in the reverse order everything was built in: kill anything still running as the account, remove the cron jobs and logrotate rule and installed scripts, unmount the tmpfs, delete the logs, then delete the account itself. Afterward `id`, `mount`, and `ps` were all checked again to confirm nothing was left behind. The script is written so it will not blow up if run twice or if an earlier step already partly failed. Script: `04_cleanup.sh`.

## A few things worth remembering

tmpfs is backed by memory, not disk, so a size limit is not optional, it is the only thing stopping it from taking down the whole machine.

Watching a load test is not the same as running it. The interesting part is what `free`, `top`, `df`, and `dmesg` show while the stress is happening, not just whether the stress command exits without an error.

Changing SSH settings on a real server is where things get risky. Opening the new port and testing it before closing the old one is what kept me from getting locked out when the socket activation issue showed up.

A config file being valid is not the same as it being in control. sshd_config looked correct and passed `sshd -t`, but a separate systemd unit was quietly overriding it. Worth checking what is actually listening, not just what the config file says.

Cleanup should only touch what the lab actually created. Nothing outside the scope of this assignment was removed or changed.

## About the keys and IPs

No private key is committed to this repository. The key pair used during testing was generated locally on the instance and kept out of git. Any IP addresses visible in the screenshots belong to a temporary EC2 instance that no longer exists by the time this is being read.

## Where the evidence is

Everything in `Screenshots/` lines up with a step above, covering account creation, storage setup, the three stress tests plus the combined one, the SSH connection before and after hardening, the cron schedule, log rotation, and the final cleanup verification. `Observation.md` goes into more detail on the reasoning behind each step and the two issues that came up along the way.

## Status

The environment was fully torn down after testing. Final checks confirmed the account, its mount, and its processes were gone, while normal SSH access on port 22 stayed available the entire time.

## Author

Safkat
