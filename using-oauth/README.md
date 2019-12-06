
## Using Social Login with OpenShift

The Liberty SocialLogin-1.0 feature can now be configured to use Open Shift's built in OAuth server and Oauth Proxy sidecar as 
authentication providers.

Two modes of authentication are available.  The first is a standard OAuth Authorization Code flow, where a web browser accessing
an app running in Liberty will be redirected to the OpenShift OAuth server to authenticate.

The second is accepting an inbound token from the OpenShift OAuth Proxy sidecar or obtained from an Openshift API call. 
This approach requires less cluster-specific configuration.

Most users will run Liberty in a pod, however in the Authorization Code flow, Liberty can run outside the OpenShift cluster. 

In either mode, an optional JWT can be created for propagation to downstream services. 

### Process to set up Authorization code flow:

In order for Liberty to communicate with the OAuth server and the Kubernetes API server, their public keys
need to be available to Liberty as a file or environment variable.  One way to do this is to 
modify your image's Docker build to call a [script](getcerts.sh) to retrieve and store the public keys before Liberty starts. 

First you'll need to create your service account and OAuth client on OpenShift.
Once you have those values, you can create the server.xml.  In a pod, you might
want to use a config map or secret to pass this information to Liberty as environment
variables so the image is portable.

  Obtain service account token:

  ```
  # create service account 
  oc project openshift
  oc create sa token-checker-01  
  # give the account auth-delegator role
  oc adm policy add-cluster-role-to-user system:auth-delegator system:serviceaccount:openshift:token-checker-01
  # get token to supply to Liberty (you MUST be in the openshift namespace when you do this)     
  oc serviceaccounts get-token token-checker-01
  ```

  Figure out the redirectURIs that your liberty server will use:
  * Liberty will request a redirect back to itself when it sends the browser to the oauth server for an authorization code.
  * This redirect URI has to be pre-registered with the authorization server.
  * It's going to be `https://(client host):(client port)/ibm/api/social-login/redirect/(oauthLogin id in server.xml)`
  * Substitute the values host:port where liberty will be running. In openShift, it will usually be
       `https://(image)-(project).apps.host/ibm/api/social-login/redirect/(oauthLogin id in server.xml)`

   
  Register a client Id and secret to supply to Liberty, using your redirectURIs 
  (adjust URIs for your image name, cluster name, and project).

  ```
  oc create -f <(echo '
	kind: OAuthClient
	apiVersion: v1
	metadata:
	  name: clientb02
	secret: secretb02
	redirectURIs:
	  - "https://localhost:8946/ibm/api/social-login/redirect/openshiftLogin"
	  - "https://social-bruce1.apps.papains.os.fyre.ibm.com/ibm/api/social-login/redirect/openshiftLogin" 
	grantMethod: prompt 
	')
  ```

Construct server.xml and specify or reference variables for the client Id, secret, OAuth URLs, and service account token
  * [sample server.xml](server.xml_authflow)
  * [sample server.env](server.env_authflow)


Sample [Docker file for authorization flow](Dockerfile_auth). 

This file builds an image that includes a local copy of Liberty.  Once 20001 is available, that image and Dockerfile can be used as a starting point instead.

Once your docker image is built and pushed you can create your deployment, service, and route to make it accessible. 
( `oc apply -f myfile.yaml` ).  
Sample 311 version yaml is [here](authorization_flow_openshift311.yaml).
Sample 42 version yaml is [here](authflow_42.yaml).  Edit as needed for your project and image name.


### Process to set up using OAuth Proxy sidecar 

An advantage of using the Proxy is there is no need to create the OAuthClient object, hence no need to define the redirect URI's with the hostname of the cluster, and only one endpoint (the Kube tokenreview endpoint) is needed in server.xml.   The 
token review endpoint URL can be set to https://kubernetes.default.svc/apis/authentication.k8s.io/v1/tokenreviews.
There's no need to retrieve certificates, as the only one needed is for the API server and Kubernetes makes it available in pods at /var/run/secrets/kubernetes.io/serviceaccount/ca.crt.   A docker image configured this way is portable across clusters with less configuration.

Construct server.xml and specify or reference a variables for the service account token
  * [sample server.xml](server.xml_proxy)
  * [sample server.env](server.env_proxy)

Create a new project (this step is required because some of us are sharing the same 42 OCP cluster)

Run ( `oc new-project projectName` )

Build and push the docker image since the config is different for the oauth proxy flow.
Sample [Docker file for oauth proxy flow](Dockerfile_proxy)
Update the [sample yaml file](libertyrp_oauthproxy_setup.yaml) and replace "CHANGEME" in the file with the new project name.

Run ( `oc apply -f myfile.yaml` ) 

It creates the deployment, service account, service and then updates the deployment and add oauth proxy container and creates the route.


### Not working?  With varying clusters, server names, image names, project names, and URL's, it's easy to miss something. Here are some things to check.

No pod running? Check that..
  * Server starts up locally and you can access the (unprotected) splash page.
  * Name of server matches command in docker file.

Browser shows some json about "invalid client"? Check that.. 
  * Redirect URI's in the OauthClient object must match the hostname being used
  * If in doubt, scrape the browser URL when things stop and compare.  Delete, edit, and recreate the OauthClient if needed.

"Application is not available" when accessing the pod or pod's protected app? 
  * Try to access the unprotected splash screen instead at /.  If you can, it's probably something in the route or service, or you entered the wrong URL. If you can't, check that pod is running and you entered a valid URL. 
  * Check that project used and name of image are consistent in yaml file.
    * For example, if image is image-registry.openshift-image-registry.svc:5000/default/libertyrp2 then project needs to be "default" and URL needed to access the pod is going to be libertyrp2-default.apps.(your cluster)

401 or 403
  * Use the OpenShift Console to access the pod's Liberty logs to get more details.   Check your server.xml against one of the examples for discrepancies.
Our goal is that the Liberty messages should be adequate to diagnose the problem.  

Something else not covered here? 
  * We know more about Liberty than Open Shift but we'd still like to hear about it.  You can [ask a question on StackOverflow](https://stackoverflow.com/tags/open-liberty).  
