# demo-oauth2-proxy

In my previous post - https://developers.redhat.com/blog/2020/08/03/authorizing-multi-language-microservices-with-louketo-proxy/  I explained how to use Louketo-Proxy to provide authentication and authorization to your microservice. Since then, the Louketo-Proxy project has become end-of-life and the developers are recommending the oauth2-proxy project as an alternative. 

This repo explains how to use oauth2-proxy with KeyCloak to provide authentication to your microservice. 

## Deploy KeyCloak

```bash
export PROJECT="keyauth"
oc new-project ${PROJECT}
oc new-app --name sso \
    --image=quay.io/keycloak/keycloak:18.0 \
    -e KEYCLOAK_ADMIN='admin' \
    -e KEYCLOAK_ADMIN_PASSWORD='oauth2-demo' \
    -e KC_PROXY='edge' \
    -n ${PROJECT}

oc patch deployment sso -p '{"spec": {"template": {"spec": {"containers": [{ "name": "sso", "command": ["/opt/keycloak/bin/kc.sh"], "args": ["start-dev", "--proxy edge"]}]}}}}'

oc create route edge --service=sso --insecure-policy=Redirect -n ${PROJECT}
```

## All-in-One

The instructions below explain how to configure KeyCloak along with how to configure and deploy the application. To make life easier you can just run the all_in_one.sh script to do this. Take note of the testuser's username and password. The password is randomly generated.

```bash
./all_in_one.sh keyauth
------Setting Exports------
setting appUrls
set appUrl apps-crc.testing
setting cookieSecret
set cookieSecret 1HNDVO3wYq-hP2xvIL4tPA==
setting oauth2ContainerUrl
set oauth2ContainerUrl quay.io/oauth2-proxy/oauth2-proxy:latest
Setting SSOBaseURL and AppBaseURL
SSO Url: https://sso-keyauth.apps-crc.testing
App Url: https://flask-keyauth.apps-crc.testing

------Configure KeyCloak Client------
setting ssoPubKey
setting ACCESS_TOKEN
Create CLIENT
Get CLIENT ID
client id: 0f44ce51-8ff9-41dd-bab6-0629521e2e01
setting clientSecret
{"type":"secret","value":"**************************************************"}
Getting clientSecret

------Configure Users and Groups------
Create Groups
Create Users
testuser username: testuser
testuser password: U1Px7u24jrM

------Deploy App------
configmap/oauth-config created
configmap/sso-public-key created
deploymentconfig.apps.openshift.io/flask created
service/flask created
route.route.openshift.io/flask created
```

### Configure KeyCloak
#### Create a Client
Log in to the KeyCloak with the username: admin and password: oauth2-demo. Once there, select Clients from the left-hand menu and create a new client with the fields shown in the figure below.

![SSO Client](images/01_create_client.png?raw=true "SSO Create Client")

After you have created the client, you will have the option to switch the client access type from public to confidential, as shown in the figure below.

![SSO Access Type](images/02_confidential.png?raw=true "SSO Acecss Type")

You will see a new tab “Credentials” appear after clicking save on the client protocol of confidential. Select the tab, and take note of the generated secret. 

Finally you need to set a valid callback url - this will be similar to the KeyCloak url, but instead of the prefix sso it will have flask:

For example if you KeyCloak url is: https://sso-keyauth.apps-crc.testing. Then set the Valid Redirect URIs to be https://flask-keyauth.apps-crc.testing/oauth2/callback as shown in the figure below:

![SSO Callback URL](images/03_callback_url.png?raw=true "SSO Callback URL")

#### Configure the mappers
Applying a Group Mapper is optional, but it does allow us to pass the group memberships of our users through to our microservice as “X-Forwarded-Groups” which is useful for informing authorisation functions within the microservice. 

##### Select the Mappers tab and add Group and Audience mapper:

Oauth2-proxy requires that you creat a mapper with:
* Mapper Type 'Group Membership' and Token Claim Name 'groups'.
* Mapper Type 'Audience' and Included Client Audience and Included Custom Audience set to your client name.

Remember to unselect the Full group path option as shown in the diagram below:

![SSO Group Mapper](images/04_groups_mapper.png?raw=true "SSO Group Mapper")


##### Configure the user groups
Now select Groups from the left-hand menu and add two groups:
* admin
* basic_user

#### Configure the user
Again from the left-hand menu, select Users and add a user. Be sure to enter an email and set a password for the user, then add the user to the basic_user and admin groups that you just created. Next, we’ll configure Ouath2 Proxy and the example application.

## Deploy the application
```
# deploy flask with oauth2-proxy in project keyauth
./create_app.sh keyauth
```

or run the following commands manually

```bash
export PROJECT="keyauth"
export appsUrl=`oc get route sso -o template --template '{{.spec.host}}' | cut -d '.' -f 2-`
export cookieSecret=`python -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(16)).decode())'`
export oauth2ContainerUrl="quay.io/oauth2-proxy/oauth2-proxy:latest"
export SSOBaseURL="https://sso-${PROJECT}.${appsUrl}"
export AppBaseURL="https://flask-${PROJECT}.${appsUrl}"
export ssoPubKey=`curl -k -s ${SSOBaseURL}/realms/master | jq -r '.public_key'`

ACCESS_TOKEN=`curl -k -s ${SSOBaseURL}/realms/master/protocol/openid-connect/token -H 'Content-Type: application/x-www-form-urlencoded' -d 'grant_type=password&username=admin&password=oauth2-demo&client_id=admin-cli' | jq -r .access_token`

CLIENT=`curl -k -s ${SSOBaseURL}/admin/realms/master/clients -H 'Content-Type: application/json' -H  "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r -c '.[] | select (.clientId | contains("oauth2-proxy")) | .id'`

echo "setting clientSecret"
curl -k -s -X POST ${SSOBaseURL}/admin/realms/master/clients/${CLIENT}/client-secret -H 'Content-Type: application/json' -H  "Authorization: Bearer ${ACCESS_TOKEN}"

echo "Getting clientSecret"
export clientSecret=`curl -k -s ${SSOBaseURL}/admin/realms/master/clients/${CLIENT}/client-secret -H 'Content-Type: application/json' -H  "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r .value`

echo "------Deploy App------"
cat oc_templates/*.yml | envsubst '${PROJECT} ${oauth2ContainerUrl} ${appsUrl} ${ssoPubKey} ${clientSecret} ${cookieSecret}' |  oc apply -n ${PROJECT} -f -
oc create route edge --service=flask --port 4180 -n ${PROJECT}
```

## Test the configuration

Once deployed, it's time to test the configuration, browse to the example application. You will be presented with a login screen. Click “Sign In with KeyCloak”. (remember to sign out of the admin portion of KeyCloak before trying to sign into the web app).

![oauth2 login](images/05_sign_in.png?raw=true "oauth2 login")

You will be redirected to Keycloak and presented with a login screen. Enter the username and password for your application user.

![SSO login](images/06_login_sso.png?raw=true "SSO login")

Once you have authenticated the user, you will be redirected to an application page that returns a JSON file. The file exposes the headers passed along by oauth2-proxy, as shown below.

![App](images/07_json.png?raw=true "App")
