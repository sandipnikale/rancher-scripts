# Secret migrator errors after upgrade to rancher 2.6.7

#!/bin/sh
set -e 
DRIVER=rancherKubernetesEngine
PREFIX=00360298
if ! command -v "grep" &> /dev/null; then
echo "Missing grep"
exit 1
fi
if ! command -v "jq" &> /dev/null; then
echo "Missing jq"
exit 1
fi
if ! command -v "awk" &> /dev/null; then
echo "Missing awk"
exit 1
fi
if ! command -v "sed" &> /dev/null; then
echo "Missing sed"
exit 1
fi
if ! command -v "kubectl" &> /dev/null; then
echo "Missing kubectl"
exit 1
fi
for i in $(kubectl get clusters.management.cattle.io | grep -v local | grep -v NAME | awk '{print $1}'); do
READY=NO
START=NO
echo "About to start modifying cluster $i. Ready? If so, enter 'YES' exactly without the '"
read -e START
if [ "$START" != "YES" ]; then
echo "Not modifying cluster $i."
continue
fi
echo Modifying cluster $i;
CLUSTERJSON=$(kubectl get clusters.management.cattle.io $i -o json)
echo $CLUSTERJSON > $PREFIX-old-cluster-$i.json
if [ "${DRIVER}" != $(echo $CLUSTERJSON | jq -r .status.driver) ]; then
echo "Cluster $i was not a cluster with driver ${DRIVER}, not modifying"
continue
fi
# First step is to capture the service account token into a secret.
if [ "null" != $(echo $CLUSTERJSON | jq -r .status.serviceAccountTokenSecret) ]; then
echo "Cluster $i already had a defined serviceAccountTokenSecret already. Not mutating."
continue
fi
CLUSTER_UID=$(echo $CLUSTERJSON | jq -r .status.serviceAccountToken)
TOKEN=$(echo $CLUSTERJSON | jq -r .status.serviceAccountToken)
if [ "${TOKEN}" == "null" ]; then
echo "Token was not set. Not mutating".
continue
fi
CLUSTERUID=$(echo $CLUSTERJSON | jq -r .metadata.uid)
if [ "${CLUSTERUID}" == "null" ]; then
echo "Cluster $i UID not found, not mutating"
continue
fi
cat << EOF > $PREFIX-secret-$i.yaml
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  generateName: cluster-serviceaccounttoken-
  namespace: cattle-global-data
  labels:
    createdfor: "$PREFIX"
  ownerReferences:
  - apiVersion: management.cattle.io/v3
    kind: Cluster
    name: $i
    uid: $CLUSTERUID
stringData:
  credential: $TOKEN
EOF
SECRET_NAME=$(kubectl create -f $PREFIX-secret-$i.yaml | awk '{print $1}' | sed 's/secret\///g')
NOW=$(date +%Y-%m-%dT%H:%M:%SZ)
echo $CLUSTERJSON | jq -r '.status.conditions[.status.conditions|length] |= . + {"lastUpdateTime":"'${NOW}'", "status":"True","type":"ServiceAccountSecretsMigrated"}' | jq -rc '.status.serviceAccountTokenSecret = "'${SECRET_NAME}'"' | jq -rc '.status.serviceAccountToken = ""' > $PREFIX-new-cluster-$i.json
cat $PREFIX-new-cluster-$i.json | jq -r
echo "About to replace cluster with the JSON above. Ready? If so, enter 'YES' exactly without the '"
read -e READY
if [ "$READY" != "YES" ]; then
echo "Not ready. Not mutating cluster $i"
continue
fi
kubectl replace -f $PREFIX-new-cluster-$i.json
echo Modified cluster $i
done
