## On-premises specific requirements

### External load balancer/HAProxy 
In cloud based deployments, a load balancer from the given cloud provider (e.g. ELB in AWS) can be used to forward traffic to the ingress controller in the k3s cluster.
However, for onprem deployments, a load balancer must be provisioned to handle this traffic. 
Currently, the recommended approach is to configure a pair of haproxy servers in a load balanced configuration which will forward traffic to the ingress controller in the cluster which is configured using a LoadBalancer service type via ServiceLB. See https://rancher.com/docs/k3s/latest/en/networking/ for details.

The HAProxy servers will share a virtual IP with failover handled by keepalived. The diagram below from [this digital ocean post](https://www.digitalocean.com/community/tutorials/how-to-set-up-highly-available-haproxy-servers-with-keepalived-and-floating-ips-on-ubuntu-14-04) explains this process quite well;
 ![HA Diagram Animated](docs/ha-diagram-animated.gif "HA Diagram Animated")


- During configuration, enter `yes` when prompted if you want to configure an onprem haproxy, then enter the required IP address for the primary, secondary and virtual IP
- Note: All DNS entries should be configured to use the Virtual IP
- Install k3s on the target master and agent nodes 
- Run `make ansible-playbook -- haproxy.yml` to install and configure haproxy and keepalived on the haproxy instances
  - Note: If not already configured, you can run `make reconfigure` to enable haproxy and enter the required variables
- If the DNS and Ingress have been configured correctly, you should now be able to use your browser to access any services which have created an Ingress object in the cluster.
- Note: All traffic will be served over https, there is a http to https redirect configured in the nginx-ingress by default.


Alternatively, if configuring HAProxy manually;
- Copy the required SSL cert to a path on the haproxy server (somewhere under /etc/haproxy or /etc/ssl/certificates would make sense)
- Run `make onprem-haproxy-cfg`, enter the path to the cert above this will output the required frontend/backend config sections for haproxy
- SSH to haproxy server, copy and paste above config sections into the haproxy.cfg (`/etc/haproxy/haproxy.cfg`) file
- Restart haproxy service `sudo service haproxy restart`
- If the DNS and Ingress have been configured correctly, you should now be able to use your browser to access any services which have created an Ingress object in the cluster.
- Note: All traffic will be served over https, there is a http to https redirect configured in the nginx-ingress by default. 