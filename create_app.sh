#!/bin/bash

if [[ -z $1 ]] && [[ -z $PROJECT ]]; then
    echo "Pass project into script of set PROJECT env var"
    exit 1
fi

if [[ -z $PROJECT ]]; then
   export PROJECT="${1}"
fi

echo "setting exports"
echo "setting appUrls"
export appsUrl=`oc get route sso -o template --template '{{.spec.host}}' | cut -d '.' -f 2-`
echo "set appUrl ${appsUrl}"
echo "setting cookieSecret"
export cookieSecret=`python -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(16)).decode())'`
echo "set cookieSecret ${cookieSecret}"
echo "setting oauth2ContainerUrl"
export oauth2ContainerUrl="quay.io/oauth2-proxy/oauth2-proxy:latest"
echo "set oauth2ContainerUrl ${oauth2ContainerUrl}"
export SSOBaseURL="https://sso-${PROJECT}.${appsUrl}"
export AppBaseURL="https://flask-${PROJECT}.${appsUrl}"

echo "setting ssoPubKey"
export ssoPubKey=`curl -k -s ${SSOBaseURL}/realms/master | jq -r '.public_key'`
# debug
# echo "set ssoPubKey ${ssoPubKey}"

echo "setting ACCESS_TOKEN"
ACCESS_TOKEN=`curl -k -s ${SSOBaseURL}/realms/master/protocol/openid-connect/token -H 'Content-Type: application/x-www-form-urlencoded' -d 'grant_type=password&username=admin&password=oauth2-demo&client_id=admin-cli' | jq -r .access_token`
# debug
# echo "${ACCESS_TOKEN}"

echo "Get CLIENT"
CLIENT=`curl -k -s ${SSOBaseURL}/admin/realms/master/clients -H 'Content-Type: application/json' -H  "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r -c '.[] | select (.clientId | contains("oauth2-proxy")) | .id'`
echo "client id: $CLIENT"

echo "setting clientSecret"
curl -k -s -X POST ${SSOBaseURL}/admin/realms/master/clients/${CLIENT}/client-secret -H 'Content-Type: application/json' -H  "Authorization: Bearer ${ACCESS_TOKEN}"

echo "Getting clientSecret"
export clientSecret=`curl -k -s ${SSOBaseURL}/admin/realms/master/clients/${CLIENT}/client-secret -H 'Content-Type: application/json' -H  "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r .value`
echo "$clientSecret"

echo "------Deploy App------"
cat oc_templates/*.yml | envsubst '${PROJECT} ${oauth2ContainerUrl} ${appsUrl} ${ssoPubKey} ${clientSecret} ${cookieSecret}' |  oc apply -n ${PROJECT} -f -
oc create route edge --service=flask --port 4180 -n ${PROJECT}
