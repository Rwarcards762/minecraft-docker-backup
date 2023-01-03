# minecraft-docker-backup

Bash script for backing up a running binhex-minecraftserver Docker container. Made as an alternative to using CA Backup plugin.

Intended to be set in a `root` owned directory, run as `root` as a `cron` job on a daily schedule. Comments in the script itself give a bit more insight.

Takes no arguments, but has variables in the script to be set as needed:

```bash
# Where to store backups (i.e. a share folder on the RAID array for data redundancy)
BACKUP_PATH="/mnt/disk1/minecraft_backups"

# Name of docker container
CONTAINER_NAME="binhex-minecraftserver-spigot"

# Name of user running the Minecraft server in Docker container
DOCKER_USER="nobody"

# Alternate user to allow multiple connections (web terminal and backup messages at same time)
DOCKER_CONNECT_USER="root" 

# Path to docker container files, i.e. an SSD Cache appdata folder in unRAID
CONTAINER_FILES_MC_PATH="/mnt/cache/appdata/binhex-minecraftserver-spigot"
```

It's nothing perfect, but has basic error checking for:

- ensuring the container exists
- ensuring the backup path and minecraft folder path exist
- ensuring the `screen` session specified exists under the user specified

It's pretty well commented (or is self explanatory based on the print statements.) Feel free to fork and use as desired, or take it as is and just update the variables to what you need.

Only things that are "hard coded" are the `screen` session name (as `minecraft`) and some of the delays being used.
