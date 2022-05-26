
#!/bin/bash

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

exit 0
