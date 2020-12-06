# demo-oauth2-proxy

This repo explains how to use oauth2-proxy with KeyCloak to provide authentication to your microservice. 

## Deploy KeyCloak

```bash
export PROJECT="keyauth"
oc new-project ${PROJECT}
oc new-app --name sso \
    --docker-image=quay.io/keycloak/keycloak \
    -e KEYCLOAK_USER='admin' \
    -e KEYCLOAK_PASSWORD='oauth2-demo' \
    -e PROXY_ADDRESS_FORWARDING='true' \
    -n ${PROJECT}

oc create route edge --service=sso -n ${PROJECT}
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

##### Select the Mappers tab and add mapper:
Groups:
* Name: groups
* Mapper type: Group Membership
* Token claim name: groups

Remember to unselect the Full group path option as shown in the diagram below:

![SSO Group Mapper](images/02_confidential.png?raw=true "SSO Group Mapper")


##### Configure the user groups
Now select Groups from the left-hand menu and add two groups:
* admin
* basic_user

#### Configure the user
Again from the left-hand menu, select Users and add a user. Be sure to enter an email and set a password for the user, then add the user to the basic_user and admin groups that you just created. Next, we’ll configure Louketo Proxy and the example application.

## Build oauth2-proxy
The current release of the oauth2-proxy is 6.1.1. One of the features we are showing is how groups can be forwarded through from KeyCloak to the microservice. 

Unfortunately, version 6.1.1 does not currently support this for the generic OpenID Connect Provider. However, the pre-release version 7 supports group forwarding, but you will need to build the container manually. Thankfully OpenShift can do this for us. 

```bash
oc new-build https://github.com/oauth2-proxy/oauth2-proxy.git --strategy=docker
```

If you do not require the group forward capability set the oauth2ContainerUrl to quay.io/oauth2-proxy/oauth2-proxy within the create_app.sh file

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
export oauth2ContainerUrl="image-registry.openshift-image-registry.svc:5000/${PROJECT}/oauth2-proxy"
export ssoPubKey=`curl -s https://sso-${PROJECT}.${appsUrl}/auth/realms/master | jq -r .public_key`


export ACCESS_TOKEN=`curl -s https://sso-${PROJECT}.${appsUrl}/auth/realms/master/protocol/openid-connect/token -H 'Content-Type: application/x-www-form-urlencoded' -d 'grant_type=password&username=admin&password=oauth2-demo&client_id=admin-cli' | jq -r .access_token`
export CLIENT=`curl -s https://sso-${PROJECT}.${appsUrl}/auth/admin/realms/master/clients -H 'Content-Type: application/json' -H  "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r -c '.[] | select (.clientId | contains("oauth2-proxy")) | .id'`
export clientSecret=`curl -s https://sso-${PROJECT}.${appsUrl}/auth/admin/realms/master/clients/${CLIENT}/client-secret -H 'Content-Type: application/json' -H  "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r .value`

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