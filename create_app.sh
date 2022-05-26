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
export oauth2ContainerUrl="quay.io/oauth2-proxy/oauth2-proxy:v7.1.3"
echo "set oauth2ContainerUrl ${oauth2ContainerUrl}"
echo "setting ssoPubKey"
export ssoPubKey=`curl -s https://sso-${PROJECT}.${appsUrl}/auth/realms/master | jq -r .public_key`
echo "set ssoPubKey ${ssoPubKey}"

echo "setting ACCESS_TOKEN"
ACCESS_TOKEN=`curl -s https://sso-${PROJECT}.${appsUrl}/auth/realms/master/protocol/openid-connect/token -H 'Content-Type: application/x-www-form-urlencoded' -d 'grant_type=password&username=admin&password=oauth2-demo&client_id=admin-cli' | jq -r .access_token`

echo "setting CLIENT"
CLIENT=`curl -s https://sso-${PROJECT}.${appsUrl}/auth/admin/realms/master/clients -H 'Content-Type: application/json' -H  "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r -c '.[] | select (.clientId | contains("oauth2-proxy")) | .id'`

echo "setting clientSecret"
export clientSecret=`curl -s https://sso-${PROJECT}.${appsUrl}/auth/admin/realms/master/clients/${CLIENT}/client-secret -H 'Content-Type: application/json' -H  "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r .value`

echo "Deploy App"
cat oc_templates/*.yml | envsubst '${PROJECT} ${oauth2ContainerUrl} ${appsUrl} ${ssoPubKey} ${clientSecret} ${cookieSecret}' |  oc apply -n ${PROJECT} -f -
oc create route edge --service=flask --port 4180 -n ${PROJECT}

