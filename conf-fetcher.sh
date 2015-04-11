#!/bin/bash

# set -e

CONFIG_PREFIX="C"
CONFIG_DELIMITER=";"
SSH_KEY_DELIMITER="#"

configs_keys=()
configs_values=()

# UNSET ALL ENV VARIABLES AFTER USING?
# http://s3.amazonaws.com/bucketname/my-plugin.zip?AWSAccessKeyId=123&amp;Expires=456&amp;Signature=abcdef
# https://s3.amazonaws.com/doc/s3-developer-guide/RESTAuthentication.html
# https://api.github.com/repos/{accountname}/{repo_slug}/contents/{path}
# https://bitbucket.org/api/1.0/repositories/{accountname}/{repo_slug}/raw/{revision}/{path}

for i in _ {a..z} {A..Z}; do
	for envar in `eval echo "\\${!$i@}"`; do
			if [[ $envar =~ ^$CONFIG_PREFIX[0-9][0-9]?$ ]]; then
				configs_keys+=($envar)
				value="$envar[@]"
				configs_values+=("${!value}")
			fi
	done
done

for i in "${!configs_values[@]}"; do
	config_array=(${configs_values[$i]//$CONFIG_DELIMITER/ })
	# 0: source 1: destination
	if [[ -n "${config_array[0]}" ]] && [[ -n "${config_array[1]}" ]]; then
		if [[ ${config_array[0]} =~ ^https?://.+ ]] || [[ ${config_array[0]} =~ ^ftps?://.+ ]]; then
			accept="*/*"
			if [[ ${config_array[0]} =~ ^https://api.github.com/.+ ]]; then
				accept="application/vnd.github.v3.raw"
			fi
			curl -H "Accept: ${accept}" -sfL ${config_array[0]} -o downloaded_file
			if [ $? != 0 ]; then
				echo "Failed to download ${configs_keys[$i]} (${config_array[0]})!"
				continue
			else
				echo "Downloaded ${configs_keys[$i]} (${config_array[0]}) succesfully!"
			fi
			
		elif [[ ${config_array[0]} =~ ^sftp://.+ ]]; then
			config_ssh_key="${configs_keys[$i]}_SSH_KEY"
			if [[ -z "${!config_ssh_key}" ]]; then
				echo "Trying to use sftp for ${configs_keys[$i]} but ${configs_keys[$i]}_SSH_KEY was not set! Skipping.."
				continue
			fi
			echo ${!config_ssh_key} | tr $SSH_KEY_DELIMITER '\n' > keyfile
			chmod 600 keyfile
			# Strip sftp:// from the beginning and set as variable $address
			address=`echo ${config_array[0]} | cut -c 8-`
			# If the address has a format of host:port, extract the port as variable $port
			port=`echo $address | grep -o -P ':(\d+)/' | cut -c 2- | rev | cut -c 2- | rev`
			address=`echo $address | sed 's#:[[:digit:]]\+/#/#' | sed 's#/#:/#'`
			port=${port:=22}
			
			# https://stackoverflow.com/questions/687948/timeout-a-command-in-bash-without-unnecessary-delay
			( sftp -q -oLogLevel=ERROR -oPort=$port -oPasswordAuthentication=no -oChallengeResponseAuthentication=no \
				-oIdentityFile=keyfile -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null $address downloaded_file ) & pid=$!
			( sleep 5 && kill -HUP $pid ) 2>/dev/null & watcher=$!
			wait $pid 2>/dev/null && pkill -HUP -P $watcher
			
			if [ $? != 0 ]; then
				echo "Failed to download ${configs_keys[$i]} (${config_array[0]})!"
				rm -f keyfile
				continue
			else
				echo "Downloaded ${configs_keys[$i]} (${config_array[0]}) succesfully!"
				rm -f keyfile
			fi
		else
			echo "Source type for ${configs_keys[$i]} was not recognized!"
			continue
		fi
		
		if [[ ${config_array[0]} =~ .+\.(zip|tar(\.(bz2|gz))?)$ ]]; then
			mkdir -p ${config_array[1]}
			mkdir extracted_download
			if [[ ${config_array[0]} =~ .+\.zip$ ]]; then
				if hash unzip 2>/dev/null; then
					unzip -q downloaded_file -d extracted_download
				else
					echo "Config ${configs_keys[$i]} is a .zip file but unzip is not installed!"
					continue
				fi
			elif [[ ${config_array[0]} =~ .+\.tar$ ]]; then
				tar -xf downloaded_file -C extracted_download
			elif [[ ${config_array[0]} =~ .+\.tar\.gz$ ]]; then
				tar -zxf downloaded_file -C extracted_download
			elif [[ ${config_array[0]} =~ .+\.tar\.bz2$ ]]; then
				tar -jxf downloaded_file -C extracted_download
			fi
			cp -rf extracted_download/* ${config_array[1]}
			rm -rf downloaded_file extracted_download
		else
			mkdir -p $(dirname ${config_array[1]})
			mv -f downloaded_file ${config_array[1]}
		fi
		
		own="${configs_keys[$i]}_CHOWN"
		if [[ -n "${!own}" ]]; then
			chown -R ${!own} ${config_array[1]}
		fi
		
		mod="${configs_keys[$i]}_CHMOD"
		if [[ -n "${!mod}" ]]; then
			chmod -R ${!mod} ${config_array[1]}
		fi
	else
		echo "Source and/or destination not set for ${configs_keys[$i]}! Skipping.."
	fi
done