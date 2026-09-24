# Observation.md

## Part 1: Identity

The service account bgdsvc_safkat was created with /usr/sbin/nologin as the login shell, as specified in Part 1. `id` and `getent passwd` confirmed the account existed with no valid login shell, which matches the intent of a dedicated service account that should never be used for interactive logins.

## Part 2 and 3: Storage and Stress Testing

The tmpfs scratch space was mounted at /mnt/bgdsvc_safkat_tmp with a 256M size cap. Filling the disk with dd showed usage climbing toward the cap without crashing the instance, confirming the size= option was doing its job.

The first attempt at the CPU stress test failed with the error "aborting: temp-path '.' must be readable and writeable". This happened because stress-ng was invoked with sudo -u bgdsvc_safkat from the ubuntu user's home directory, which the service account has no permission to write to. The fix was to explicitly point stress-ng at the tmpfs directory owned by the service account using --temp-path "/mnt/${SVC_NAME}_tmp". After this change, all three stress modes (cpu, vm, and the combined run) completed with "successful run completed" messages.

During the combined stress test, dmesg | grep -i oom initially failed with "read kernel buffer failed: Operation not permitted". This is a kernel restriction on unprivileged reads of the dmesg ring buffer, common on recent Ubuntu AMIs. Running the same command with sudo resolved it. No OOM events were recorded, which is consistent with free -h showing the system stayed within its available memory during the test.

## Part 4: SSH Access

An Ed25519 key pair was generated and installed into the service account's authorized_keys file. Connecting with ssh -i ~/.ssh/bgdsvc_safkat_key bgdsvc_safkat@localhost completed the full key exchange and authentication successfully, shown by the Ubuntu welcome banner and system information being printed. The session then closed with "This account is currently not available", which is the expected behavior for a nologin shell rather than an error. This confirmed that public-key authentication was working correctly while still keeping the account non-interactive, in line with the security reasoning given in Part 1.

## Part 5: SSH Hardening

Before editing sshd_config, TCP port 2222 was added to the EC2 security group alongside the existing port 22 rule, so the new configuration could be tested without risking a lockout. Port 22 was left in place during testing as a fallback.

After adding Port 2222, PermitRootLogin no, PasswordAuthentication no, and AllowUsers bgdsvc_safkat to sshd_config and restarting the ssh service, the new port did not immediately take effect. sshd -T correctly reported port 2222 as the configured value, but ss -tlnp showed sshd still listening only on port 22. The cause was systemd socket activation: on this Ubuntu version, ssh.socket controls the actual listening port independently of sshd_config, and it was still bound to port 22 from boot.

Running sudo systemctl disable --now ssh.socket followed by sudo systemctl enable --now ssh.service resolved this by letting sshd bind directly to the port defined in its own config file. After this change, ss -tlnp showed sshd listening on 0.0.0.0:2222 and [::]:2222, and a new SSH connection using the service account's key succeeded on port 2222, again ending in the expected "This account is currently not available" message.

A second terminal session on port 22 was kept open throughout this process as a safety net in case the port 2222 change failed, though it was never needed since the fallback access remained available the whole time.

## Part 6: Monitoring and Cron

Both the monitor script and the cleanup script were created under /usr/local/bin and made executable. The monitor script was tested manually first with sudo -u bgdsvc_safkat before trusting it to cron, and it correctly appended a timestamped block containing free -h, df -h for the tmpfs directory, and ps -u output to /var/log/bgdsvc_safkat/monitor.log.

The crontab was installed for the service account using sudo crontab -e -u bgdsvc_safkat, with entries to run the monitor script every 5 minutes and the cleanup script nightly at 2 AM. Confirmation that cron was actually running the job automatically, not just capable of running it, came from monitor.log itself: two separate timestamped entries appeared five minutes apart without any manual command being run in between.

The cleanup script was not manually triggered during testing, since the tmpfs still contained the files generated during the Part 3 stress test and there was no need to remove them early.

## Part 7: Log Rotation

A logrotate rule was created at /etc/logrotate.d/bgdsvc_safkat targeting /var/log/bgdsvc_safkat/*.log, with daily rotation, 5 rotations kept, compression enabled, missingok and notifempty set, a 10M size threshold, and new logs created with 0640 permissions owned by bgdsvc_safkat.

Before forcing a rotation, monitor.log already contained several entries from the cron job running in the background. Running sudo logrotate -f /etc/logrotate.d/bgdsvc_safkat produced no output, which is normal for logrotate on success. Checking the log directory afterward showed a fresh, empty monitor.log and a compressed monitor.log.1.gz, both owned by bgdsvc_safkat:bgdsvc_safkat with 0640 permissions, matching the create directive exactly.

## Part 8: Cleanup

Cleanup was performed in the reverse order of how the environment was built: processes killed first, then cron and logrotate removed, then the tmpfs unmounted, then logs deleted, and finally the user account itself removed with userdel -r. Verification afterward with id, mount | grep, and ps -u confirmed the account, its mount, and its processes were all gone, matching the expected "should fail" and "should be empty" results described in the assignment.

## General Observations

Two issues came up during this assignment that were not mentioned directly in the instructions but were straightforward to diagnose from the error messages: stress-ng needing a writable temp path when run as a different user, and Ubuntu's SSH socket activation overriding sshd_config until the socket unit itself was disabled. Both were resolved without needing to touch the EC2 security group again, since the fallback port 22 session was never actually lost during the process.

If this were a real production server rather than a test environment, a few things would be done differently. The security group rule for port 2222 would be restricted to a specific IP range instead of 0.0.0.0/0. The systemd socket activation behavior would be checked and documented before relying on a port change in sshd_config, since it silently ignored the new port on the first attempt. And the cleanup script would likely need a safeguard against deleting files that are still open, rather than assuming the daily cron window is enough separation from active writes.