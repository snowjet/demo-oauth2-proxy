#!/bin/bash

if [[ -z $1 ]] && [[ -z $PROJECT ]]; then
    echo "Pass project into script of set PROJECT env var"
    exit 1
fi

if [[ -z $PROJECT ]]; then
   export PROJECT="${1}"
   oc project ${PROJECT}
fi

echo "------Setting Exports------"
echo "setting appUrls"
export appsUrl=`oc get route sso -o template --template '{{.spec.host}}' | cut -d '.' -f 2-`
echo "set appUrl ${appsUrl}"
echo "setting cookieSecret"
export cookieSecret=`python -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(16)).decode())'`
echo "set cookieSecret ${cookieSecret}"
echo "setting oauth2ContainerUrl"
export oauth2ContainerUrl="quay.io/oauth2-proxy/oauth2-proxy:latest"
echo "set oauth2ContainerUrl ${oauth2ContainerUrl}"
echo "Setting SSOBaseURL and AppBaseURL"
export SSOBaseURL="https://sso-${PROJECT}.${appsUrl}"
export AppBaseURL="https://flask-${PROJECT}.${appsUrl}"
echo "SSO URL: ${SSOBaseURL}"
echo "App URL: ${AppBaseURL}"

echo "------Configure KeyCloak Client------"
echo "setting ssoPubKey"
export ssoPubKey=`curl -k -s ${SSOBaseURL}/realms/master | jq -r '.public_key'`
# debug
# echo "set ssoPubKey ${ssoPubKey}"

echo "setting ACCESS_TOKEN"
ACCESS_TOKEN=`curl -k -s ${SSOBaseURL}/realms/master/protocol/openid-connect/token -H 'Content-Type: application/x-www-form-urlencoded' -d 'grant_type=password&username=admin&password=oauth2-demo&client_id=admin-cli' | jq -r .access_token`
# debug
# echo "${ACCESS_TOKEN}"

clientJSON='
{
    "clientId": "oauth2-proxy",
    "name": "oauth2-proxy",
    "rootUrl":"'"$AppBaseURL"'",
    "surrogateAuthRequired": false,
    "enabled": true,
    "alwaysDisplayInConsole": false,
    "clientAuthenticatorType": "client-secret",
    "redirectUris": [
        "/*"
    ],
    "webOrigins": [],
    "notBefore": 0,
    "bearerOnly": false,
    "consentRequired": false,
    "standardFlowEnabled": true,
    "implicitFlowEnabled": false,
    "directAccessGrantsEnabled": false,
    "serviceAccountsEnabled": false,
    "publicClient": false,
    "frontchannelLogout": false,
    "protocol": "openid-connect",
    "authenticationFlowBindingOverrides": {},
    "fullScopeAllowed": true,
    "nodeReRegistrationTimeout": -1,
    "protocolMappers": [
        {
            "name": "groups",
            "protocol": "openid-connect",
            "protocolMapper": "oidc-group-membership-mapper",
            "consentRequired": false,
            "config": {
                "full.path": "false",
                "id.token.claim": "true",
                "access.token.claim": "true",
                "claim.name": "groups",
                "userinfo.token.claim": "true"
            }
        },
        {
            "name": "Audience",
            "protocol": "openid-connect",
            "protocolMapper": "oidc-audience-mapper",
            "consentRequired": false,
            "config": {
                "included.client.audience": "oauth2-proxy",
                "id.token.claim": "true",
                "access.token.claim": "true",
                "userinfo.token.claim": "true"
            }
        }
    ],
    "defaultClientScopes": [
        "web-origins",
        "acr",
        "roles",
        "profile",
        "email"
    ],
    "optionalClientScopes": [
        "address",
        "phone",
        "offline_access",
        "microprofile-jwt"
    ],
    "access": {
        "view": true,
        "configure": true,
        "manage": true
    }
}'

echo "Create CLIENT"
echo $clientJSON | curl -k -X POST ${SSOBaseURL}/admin/realms/master/clients \
    -H "Content-Type: application/json" \
    -H  "Authorization: Bearer ${ACCESS_TOKEN}"  \
    -d @-

echo "Get CLIENT ID"
CLIENT=`curl -k -s ${SSOBaseURL}/admin/realms/master/clients -H 'Content-Type: application/json' -H  "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r -c '.[] | select (.clientId | contains("oauth2-proxy")) | .id'`
echo "client id: $CLIENT"

echo "setting clientSecret"
curl -k -s -X POST ${SSOBaseURL}/admin/realms/master/clients/${CLIENT}/client-secret -H 'Content-Type: application/json' -H  "Authorization: Bearer ${ACCESS_TOKEN}"

echo "Getting clientSecret"
export clientSecret=`curl -k -s ${SSOBaseURL}/admin/realms/master/clients/${CLIENT}/client-secret -H 'Content-Type: application/json' -H  "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r .value`
# debug
# echo "$clientSecret"


echo "------Configure Users and Groups------"
groupJSON='
{
    "name": "basic_user",
    "path": "/basic_user"
}'

echo "Create Groups"
echo $groupJSON | curl -k -X POST ${SSOBaseURL}/admin/realms/master/groups \
    -H "Content-Type: application/json" \
    -H  "Authorization: Bearer ${ACCESS_TOKEN}"  \
    -d @-

echo "Create Users"
userPassword=`python -c 'import secrets; print(secrets.token_urlsafe(8))'`
echo 'testuser username: testuser'
echo "testuser password: ${userPassword}"
userJSON='
{
    "username": "testuser",
    "enabled": true,
    "totp": false,
    "emailVerified": true,
    "firstName": "TestUserFirstName",
    "lastName": "TestUserLastName",
    "email": "testUser@home.net",
    "credentials": [
        {
            "type": "password",
            "value": "'"${userPassword}"'",
            "temporary": false
        }
    ],
    "groups": ["basic_user"]
}'

echo $userJSON | curl -k -X POST ${SSOBaseURL}/admin/realms/master/users \
    -H "Content-Type: application/json" \
    -H  "Authorization: Bearer ${ACCESS_TOKEN}"  \
    -d @-


groupJSON='
{
    "name": "admin",
    "path": "/admin"
}'

echo "Create Groups"
echo $groupJSON | curl -k -X POST ${SSOBaseURL}/admin/realms/master/groups \
    -H "Content-Type: application/json" \
    -H  "Authorization: Bearer ${ACCESS_TOKEN}"  \
    -d @-

echo "Create Users"
userPassword=`python -c 'import secrets; print(secrets.token_urlsafe(8))'`
echo 'testuser username: superuser'
echo "testuser password: ${userPassword}"
userJSON='
{
    "username": "superuser",
    "enabled": true,
    "totp": false,
    "emailVerified": true,
    "firstName": "Super",
    "lastName": "User",
    "email": "superuser@home.net",
    "credentials": [
        {
            "type": "password",
            "value": "'"${userPassword}"'",
            "temporary": false
        }
    ],
    "groups": ["basic_user","admin"]
}'

echo $userJSON | curl -k -X POST ${SSOBaseURL}/admin/realms/master/users \
    -H "Content-Type: application/json" \
    -H  "Authorization: Bearer ${ACCESS_TOKEN}"  \
    -d @-


echo "------Deploy App------"
cat oc_templates/*.yml | envsubst '${PROJECT} ${oauth2ContainerUrl} ${appsUrl} ${ssoPubKey} ${clientSecret} ${cookieSecret}' |  oc apply -n ${PROJECT} -f -
oc create route edge --service=flask --port 4180 -n ${PROJECT}
