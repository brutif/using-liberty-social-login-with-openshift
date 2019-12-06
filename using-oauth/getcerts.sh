#!/bin/bash

function fetchcert {   
   HOST=$1
   PORT=$2
   echo retrieving cert from ${HOST}:${PORT}   
   echo q | openssl s_client -servername ${HOST} -showcerts -connect ${HOST}:${PORT} >/tmp/temp.out 2>/dev/null
   input="/tmp/temp.out"
   state=0

	while IFS= read -r line
	do
		# go past first cert, we want the second one.
		if [[ $line == *"END CERTIFICATE"* ]] && [[ "$state" == "0" ]]; then
			#echo "found end"
			state=1
		fi

		if [[ $line == *"BEGIN CERTIFICATE"* ]] && [[ "$state" == "1" ]]; then
			#echo "found second begin"
			state=2
		fi

		if [[ $line == *"END CERTIFICATE"* ]] && [[ "$state" == "2" ]]; then
			#echo "found second end"
			state=3
			echo $line
			echo $line >>/tmp/trustedcert.pem
		fi
		if [[ "$state" == "2" ]]; then
			echo $line
			echo $line >>/tmp/trustedcert.pem
	    fi
	done < "$input"
	rm -f /tmp/temp.out
}

# If not using Docker set OAUTH_SERVER_VOST  before calling. 
# Example: export OAUTH_SERVER_VHOST=myhost.os.fyre.ibm.com
#
# In Docker OAUTH_SERVER_VHOST still needs to be set somehow. 
# To run this in a dockerfile, use ENTRYPOINT ["/opt/ol/helpers/runtime/parsecert.sh"] 
# then use CMD[ script and params to start the server ] 
rm -f /tmp/trustedcert.pem
fetchcert oauth-openshift.apps.${OAUTH_SERVER_VHOST} 443
fetchcert openshift.apps.${OAUTH_SERVER_VHOST} 6443
fetchcert api.${OAUTH_SERVER_VHOST} 6443

# env var name for Liberty must be cert_(truststore name)
export cert_defaultKeyStore=/tmp/trustedcert.pem
exec "$@"