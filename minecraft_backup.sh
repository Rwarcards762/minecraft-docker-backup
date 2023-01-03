#!/bin/sh
#####
# Script for running backups from a Minecraft server running in a Docker container
#     Copies the entire server folder out to a desired location on a disk path via rsync, for DR in case of a disk failure
#
#     The goal is since Minecraft is automatically backing up the world twice a day to its folders,
#     the short-term rsync daily are for DR rather than restorative action.
#     The built-in Minecraft backups (/backups) are for actual restorative action.
#
# Created by Christopher Rice (Rwarcards762), 1/2/2023 for unRAID 6.11.x (not that it matters) 
#     because CA Backups is a bad solution for running a server off a cache drive and cleanly backing it up
#
# Note that this is NOT perfect: If the container is restarted and the ACL is not re-set, then the backup will
#     fail if it tries to run while a Web Terminal session is running (as multi-user isn't enabled by default.)
#     There is no work-around for this other than to set up the docker image to enable multi-user mode
#     and add root to the minecraft screen ACL by default.
#####

### RETURN CODES ###
# 0: No issues, ran as desired
# 1: Standard error such as a path missing, container name not found, screen session doesn't exist
# 2: Backup was a success, but some other issue occurred that may cause trouble in the future
####################

# VARIABLES ##################################################################
# Where to store backups (i.e. a share folder on the RAID array for data redundancy)
BACKUP_PATH="/mnt/disk1/minecraft_backups"

# Name of docker container to connect to, and user to connect with
CONTAINER_NAME="binhex-minecraftserver-spigot"
DOCKER_USER="nobody" # what minecraft normally runs under
DOCKER_CONNECT_USER="root" # concurrent user to allow multiple connections
CONTAINER_FILES_MC_PATH="/mnt/cache/appdata/binhex-minecraftserver-spigot"

##############################################################################

# First, ensure the container / share path exist
docker ps | grep "$CONTAINER_NAME"
if [ $? -eq 0 ]; then
    echo "[DEBUG] Container found."
else
    echo "[ERROR] Container not found. Please verify the CONTAINER_NAME is correct."
    exit 1
fi

if [ -d "$BACKUP_PATH" ]; then
    echo "[DEBUG] Backup directory found."
else
    echo "[ERROR] Backup directory not found. Please verify the BACKUP_PATH is correct."
    exit 1
fi

if [ -d "$CONTAINER_FILES_MC_PATH" ]; then
    echo "[DEBUG] Minecraft file folder found."
else
    echo "[ERROR] Minecraft folder not found. Please verify the CONTAINER_FILES_MC_PATH is correct."
    exit 1
fi

docker exec --user $DOCKER_USER $CONTAINER_NAME screen -list | grep "No Sockets found"
if [ $? -eq 0 ]; then
    echo "[ERROR] Server may or may not be running, but Screen session does not exist to attach to. Exiting."
    exit 1
fi

# Then, we can check if the multi-user/ACLs have been set yet or not
# If "multi" is found, this means the settings have already been applied and concurrent connections should be permitted
# Otherwise, say the container got restarted, try and reapply our multi-user/ACL modes if possible
#     If we cannot, this means that the terminal is currently in use and we are unable to run any commands against it and MUST exit
docker exec --user $DOCKER_USER $CONTAINER_NAME screen -list | grep "Multi"
if [ $? -eq 0 ]; then
    echo "[DEBUG] Multi-user mode on Screen set. Backup can run even if a Web Terminal is attached."
else
    echo "[WARNING] Multi-user mode NOT set on Screen -- backup WILL FAIL if a user is connected to the Web Terminal."
    echo "[INFO] Attempting to set multiuser mode..."
    docker exec --user $DOCKER_USER $CONTAINER_NAME screen -dr -S $DOCKER_USER/minecraft -X multiuser on
    docker exec --user $DOCKER_USER $CONTAINER_NAME screen -list | grep "Multi"
    if [ $? -eq 0 ]; then
        echo "[INFO] Multiuser mode successfully set, setting ACLs and continuing backup process..."
    else
	echo "[ERROR] Unable to set multiuser mode. A user or process is connected to the Web Terminal or screen session already. Unable to change permissions. Exiting."
	exit 1
    fi
    docker exec --user $DOCKER_USER $CONTAINER_NAME screen -dr -S $DOCKER_USER/minecraft -X acladd $DOCKER_CONNECT_USER
fi

# Now, we can announce to the minecraft server that the server will be going down in 10 minutes for a backup
#     as we are certain we can connect to the screen session now
docker exec --user $DOCKER_CONNECT_USER $CONTAINER_NAME screen -dr -S $DOCKER_USER/minecraft -X stuff "say [AUTOMATIC SCRIPT] Server restarting in 10 minutes for daily backup...^M"
sleep 540
docker exec --user $DOCKER_CONNECT_USER $CONTAINER_NAME screen -dr -S $DOCKER_USER/minecraft -X stuff "say [AUTOMATIC SCRIPT] Server restarting in 1 minute for daily backup...^M"
sleep 50
echo "[DEBUG] Giving 10 second warning to server..."
docker exec --user $DOCKER_CONNECT_USER $CONTAINER_NAME screen -dr -S $DOCKER_USER/minecraft -X stuff "say [AUTOMATIC SCRIPT] Server restarting in 10 seconds for daily backup...^M"
sleep 10

# Stop server cleanly, wait for screen to exit
echo "[DEBUG] Stopping server, giving 35 seconds for process to exit..."
docker exec --user $DOCKER_CONNECT_USER $CONTAINER_NAME screen -dr -S $DOCKER_USER/minecraft -X stuff "stop^M"
# We know server has exited cleanly if the screen session exits
sleep 35
docker exec --user $DOCKER_USER $CONTAINER_NAME screen -list | grep "No Sockets found"
if [ $? -eq 0 ]; then
    echo "[DEBUG] Server has exited cleanly."
else
    echo "[DEBUG] Server has not exited after 35 seconds. Waiting for another 30 seconds before continuing."
    sleep 30
fi

# Stop container
echo "[DEBUG] Stopping docker container $CONTAINER_NAME..."
docker stop $CONTAINER_NAME

# Make copy of files now that the server has stopped running
echo "[INFO] Taking incremental backup from $CONTAINER_FILES_MC_PATH to $BACKUP_PATH..."
rsync -aAXv --delete --mkpath $CONTAINER_FILES_MC_PATH $BACKUP_PATH 
echo "[INFO] Incremental backup complete."

# Restart container
echo "[DEBUG] Starting docker container $CONTAINER_NAME..."
docker start $CONTAINER_NAME

# Allow some time for the docker container to start, then pre-set ACLs for next time this script runs
echo "[DEBUG] Waiting 30 seconds for container to wake up and server to start before pre-setting ACL/multiuser mode..."
sleep 30
docker exec --user $DOCKER_USER $CONTAINER_NAME screen -dr -S $DOCKER_USER/minecraft -X multiuser on
docker exec --user $DOCKER_USER $CONTAINER_NAME screen -dr -S $DOCKER_USER/minecraft -X acladd $DOCKER_CONNECT_USER
docker exec --user $DOCKER_USER $CONTAINER_NAME screen -list | grep "Multi"
if [ $? -eq 0 ]; then
    echo "[INFO] Multi-user and ACL set successfully. Backup script has completed. Exiting."
    exit 0
else
    echo "[WARNING] Multi-user/ACL may not have been set successfully. Investigate, as this could prevent backups in the future!"
    exit 2
fi


