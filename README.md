# trivy-example-project

This project aims to demonstrate the integration capabilities of Trivy and Resmo in a Kubernetes environment. The
repository includes a Go program that utilizes the client-go library to connect to a Kubernetes cluster and
list the pods. The chosen version of the client-go library is intentionally an older version with known
vulnerabilities, in order to demonstrate how Trivy can be used to identify these vulnerabilities and associate them
with specific running containers on the cluster. Additionally, the project showcases how the integration can be
utilized in GitHub Actions for continuous security monitoring in a Kubernetes cluster and keep track of remediation
over time.

# Step 0

Have a Kubernetes environment ready to use. In this example, we are using Minikube for demonstration purposes. Create
a [Resmo Account](https://id.resmo.app/) and add
a [Kubernetes integration](https://docs.resmo.com/product/integrations/kubernetes-integration). and 
a [Trivy integration](https://docs.resmo.com/product/integrations/trivy-integration)

```shell
$ minikube start
```

# Step 1

The Go library `client-go` and `gcr.io/distroless/base-debian9` is vulnerable. We will build the supplied image and 
add the changes

```shell
$ eval $(minkube docker-env)
// Build the image and write the Image ID to file $(imgId1) and deploy to Kubernetes cluster
$ docker build --iidfile=imgId1 -t "pod-watcher:1.0" .
$ kubectl apply -f manifest.yml

// Generate a SBOM in the Cyclonedx format of the resulting image with Trivy, and upload it to Resmo
$ trivy image --format cyclonedx $(cat imgId1) > step1.json

$ CUSTOMER_DOMAIN="acme"
$ INGEST_KEY="7c3d9dbe-48ec-411a-92ff-f159cf2f1473" # Available on the Resmo UI in Trivy Integration
$ COMPONENT="trivy-example-project"

$ curl --request POST \
  --compressed \
  --url "https://${CUSTOMER_DOMAIN}.resmo.app/integration/trivy/event?componentName=${COMPONENT}" \
  --header 'Content-Type: application/json' \
  --header "X-Ingest-Key: ${INGEST_KEY}" \
  --data "@step1.json"
  
```

By doing so, we build a vulnerable image, deployed it to our cluster. Also, we've created a SBOM file using Trivy
and uploaded it to our Resmo account. In the UI, you will be able to see it resulted in a set of vulnerabilities both
from client-go library and the base Debian image.

# Step 2

Update the base Docker image to `base-debian11`.

```diff
-FROM gcr.io/distroless/base-debian9
+FROM gcr.io/distroless/base-debian11
```

Update the client-go to the latest package and rebuild the image.

```shell
$ go get k8s.io/client-go@v0.26.1
```

Notice the versions updated from 0.18.0 to 0.26.1 in the `go.mod` file.

```diff
require (
-       k8s.io/apimachinery v0.18.0
-       k8s.io/client-go v0.18.0
+       k8s.io/apimachinery v0.26.1
+       k8s.io/client-go v0.26.1
)
```

Now we need to rebuild the Docker image, executing the same commands as above with slight difference on filenames.

```shell
$ eval $(minkube docker-env)
// Build the new image and label the container as pod-watcher:1.1
$ docker build --iidfile=imgId2 -t "pod-watcher:1.1" .
$ kubectl apply -f manifest.yml

// Generate the SBOM from new file
$ trivy image --format cyclonedx $(cat imgId2) > step2.json

// Send the new SBOM to Resmo with same componentName
$ curl --request POST \
  --compressed \
  --url "https://${CUSTOMER_DOMAIN}.resmo.app/integration/trivy/event?componentName=${COMPONENT}" \
  --header 'Content-Type: application/json' \
  --header "X-Ingest-Key: ${INGEST_KEY}" \
  --data "@step2.json"
```

After uploading, you can see on the Resmo UI that the new vulnerabilities are shown. There are few SQL 
queries that you can test:

* Show Kubernetes Pods with image IDs

```sql
SELECT metadata.namespace, metadata.name, metadata.app, status.podIP, s.image, s.imageId
FROM kubernetes_pod p, p.status.containerStatuses s
```

* Show Critical and High Vulnerabilities for an Image ID

```sql
SELECT targetType, class, vulnerabilityId, severity, title, description, pkgName, installedVersion, fixedVersion FROM trivy_vulnerability
WHERE severity IN ('CRITICAL', 'HIGH') AND imageId = 'sha256:0607a2db21a5975eecc4aba505ed9b02f80c187fb81d6242a8be2c0aac345e49'
ORDER BY vulnerabilityId DESC
```

* List Pods with Critical and High vulnerabilities present, deduplicate by app label

```sql
SELECT DISTINCT p.metadata.labels.app, p.metadata.namespace, t.vulnerabilityId, t.title, t.severity, t.pkgName, t.installedVersion, t.fixedVersion
FROM kubernetes_pod p, p.status.containerStatuses s 
JOIN trivy_vulnerability t ON ('sha256:' || split(s.imageID, 'sha256:')[1]) = t.imageId
WHERE t.severity IN ('CRITICAL', 'HIGH')
ORDER BY t.vulnerabilityId DESC
```