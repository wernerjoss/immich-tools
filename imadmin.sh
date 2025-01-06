#!/bin/bash
# dialog bash menu to control Immich Server - please check and update settings before use !
# needs https://invisible-island.net/dialog/dialog.html to be installed, also awk, wget and rsync (optional, only needed for clone)
# see also https://immich.app/docs/overview/introduction - Administration

# settings:
export IMMICH_HOME="$HOME/docker/immich-app"	#	where the immich docker-compose.yml is located (without trailing slash '/')
source $IMMICH_HOME/.env	# get UPLOAD_LOCATION, DB_DATA_LOCATION, REMOTE_DEST from .env
DB_BACKUP_LOCATION="$UPLOAD_LOCATION/backups"	#	default, same as immich app uses itself 09.11.24
if [ -z $CLONE_DB_BACKUP_LOCATION ];then
	CLONE_DB_BACKUP_LOCATION="$UPLOAD_LOCATION/backups"	#	default, same as localhost
fi

# note: REMOTE_DEST is a nonstandard Value sourced from $IMMICH_HOME/.env, it must be in the Form: <hostname>:<path> !
# end settings

if [ ! -z $REMOTE_DEST ];then
	REMOTE_HOST=`echo $REMOTE_DEST | awk -F\: '{print $1}'`
fi 

HEIGHT=18
WIDTH=0	#	45
CHOICE_HEIGHT=4
HOST=`hostname`
TITLE=" $HOST Immich Server Administration"
MENU="Choose one of the following options:"

OPTIONS=(1 "update server"
		 2 "cleanup docker images"
		 3 "remove docker volumes"
		 4 "backup database"
		 5 "restore database"
		 6 "fetch docker-compose.yml"
		 7 "start/stop server"
		 8 "rsync data to clone"
		 9 "Quit")

while [[ "$CHOICE" -ne 9 ]];do
	CHOICE=$(dialog --clear \
					--title "$TITLE" \
					--default-item '9' \
					--menu "$MENU" \
					$HEIGHT $WIDTH $CHOICE_HEIGHT \
					"${OPTIONS[@]}" \
					2>&1 >/dev/tty)

	clear
	case $CHOICE in
			1)
				echo "updating Immich Server, please wait until finished"
				pushd $IMMICH_HOME
				docker compose down && docker compose pull && docker compose up -d
				popd
				;;
			2)
				echo "cleaning up obsolete docker images"
				srvimg=`docker image ls | grep immich-server | grep release | awk '{print $3}'`
				echo "active server image: $srvimg"
				learnimg=`docker image ls | grep immich-machine-learning | grep release | awk '{print $3}'`
				echo "active machine learning image: $learnimg"
				echo "obsolete images:"
				docker image ls | grep immich-server | grep -v $srvimg
				docker image ls | grep immich-machine-learning | grep -v $learnimg
				touch $IMMICH_HOME/rmimg.sh
				docker image ls | grep immich-server | grep -v $srvimg | awk '{ printf "docker image rm %s\n", $3}' > $IMMICH_HOME/rmimg.sh
				docker image ls | grep immich-machine-learning | grep -v $learnimg | awk '{ printf "docker image rm %s\n", $3}' >> $IMMICH_HOME/rmimg.sh
				chmod +x $IMMICH_HOME/rmimg.sh
				echo "please check $IMMICH_HOME/rmimg.sh before executing it :"
				select dopt in "remove obsolete images" cancel; do
					case $dopt in
						"remove obsolete images")
						$IMMICH_HOME/rmimg.sh
						break
						;;
					cancel)
						continue 2
						;;
					esac
				done
				;;
			3)
				echo "prepare removing docker volumes (caution before actually doing this !)"
				pushd $IMMICH_HOME
				# docker compose down
				touch $IMMICH_HOME/rmv.sh
				docker volume ls | awk '{ if (NR > 1) printf "docker volume rm %s\n",$2}' > $IMMICH_HOME/rmv.sh
				chmod +x $IMMICH_HOME/rmv.sh
				echo "please check $IMMICH_HOME/rmv.sh and stop Immich Server before executing it ! (might contain volumes not related to immich !)"
				# docker compose up -d
				echo "press return to continue"
				read ans
				popd
				;;
			4)
				echo "backup Database"
				d=$(date '+%Y-%m-%d')
				dump="pgdump-$HOST-$d.tar.gz"
				backupfile=$DB_BACKUP_LOCATION/$dump
				echo $backupfile
				docker exec -t immich_postgres pg_dumpall --clean --if-exists --username=postgres | gzip > $backupfile
				if [ ! -z $REMOTE_HOST ];then
					if (ping -c 1 $REMOTE_HOST);then
						echo "copying $backupfile to $REMOTE_HOST"
						scp $backupfile "$REMOTE_HOST"":""$CLONE_DB_BACKUP_LOCATION"	# assume $DB_BACKUP_LOCATION is the same on REMOTE_HOST :-)
					fi
				fi
				;;
			5)
				echo "restore database"
				prompt="Please select a file:"
				options=( $(find $DB_BACKUP_LOCATION -type f -maxdepth 1 -print0 | xargs -0) )
				PS3="$prompt "
				select bopt in "${options[@]}" "cancel" ; do 
					if (( REPLY == 1 + ${#options[@]} )) ; then
						continue 2	# 2
					elif (( REPLY > 0 && REPLY <= ${#options[@]} )) ; then
						echo  "You picked $bopt which is file $REPLY"
						if [ -f $bopt ];then
							pushd $IMMICH_HOME
							docker compose down -v  # CAUTION! Deletes all Immich data to start from scratch
							## Uncomment the next line and replace DB_DATA_LOCATION with your Postgres path to permanently reset the Postgres database
							# rm -rf DB_DATA_LOCATION # CAUTION! Deletes all Immich data to start from scratch
							# let the user decide wether to delete $DB_DATA_LOCATION :
							co=0
							echo "delete $DB_DATA_LOCATION ? (usually not required)"
							select dopt in "delete" cancel; do
								case $dopt in
								"delete")
									echo "(sudo) Password required to cleanup $DB_DATA_LOCATION !"
									sudo rm -rf $DB_DATA_LOCATION # CAUTION! Deletes all Immich data to start from scratch
									break
									;;
								cancel)
									co=1
									break
									;;
								esac
							done
							if [ $co -gt 0 ];then
								break
							fi
							docker compose pull	 # Update to latest version of Immich (if desired)
							docker compose create   # Create Docker containers for Immich apps without running them
							docker start immich_postgres	# Start Postgres server
							echo "Waiting for Postgres server to start up.."
							repeat=1
							while [ $repeat -gt 0 ];do
								sleep 5	# Wait for Postgres server to start up
								srvstat=`docker ps | grep postgres`
								echo $srvstat
								srvstatok=`docker ps | grep postgres | grep healthy`
								if [ -z "$srvstatok" ];then
										repeat=1
								else
										repeat=0
								fi
							done
							gunzip < "$bopt" \
							| sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" \
							| docker exec -i immich_postgres psql --username=postgres	# Restore Backup
							docker compose up -d	# Start remainder of Immich apps
							echo "Waiting for Immich server to start up.."
							repeat=1
							while [ $repeat -gt 0 ];do
								sleep 5	# Wait for Postgres server to start up
								srvstat=`docker ps | grep immich-server`
								echo $srvstat
								srvstatok=`docker ps | grep immich-server | grep healthy`
								if [ -z "$srvstatok" ];then
										repeat=1
								else
										repeat=0
								fi
							done
							echo "press return to continue"
							read ans
							popd
						fi
						break	#	break
					else
						echo "Invalid option. Try another one."
					fi
				done   
				break
				;;
			6)
				pushd $IMMICH_HOME
				echo "fetch docker-compose.yml"
				cp docker-compose.yml docker-compose.yml.$$	# create backup from current docker-compose.yml
				wget -O docker-compose.yml https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml
				ls -l docker-compose*
				echo "press return to continue"
				read ans
				popd
				;;
			7)
				pushd $IMMICH_HOME
				alive=`docker ps | grep immich-server | grep healthy `
				if [ -z $alive ];then
					echo "starting Immich Server"
					docker compose up -d
					docker ps
				else
					echo "stopping Immich Server"
					docker compose down
				fi	
				echo "press return to continue"
				read ans
				popd
				;;
			8)
				if [ -z $REMOTE_DEST ];then
					echo "$REMOTE_DEST is not set, no Action taken"
					echo "press return to continue"
					read ans
				else
					if (ping -c 1 $REMOTE_HOST);then
						pushd $UPLOAD_LOCATION
						echo "rsync data to $REMOTE_DEST"
						rsync -vtr --delete * $REMOTE_DEST
						popd
					else
						echo "remote host $REMOTE_HOST is not alive, no Action taken"
						echo "press return to continue"
						read ans
					fi
				fi
				;;
			9)
				echo "Immich Admin Tool exited"
				;;
	esac
done 
