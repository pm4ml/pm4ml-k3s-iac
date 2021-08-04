# Makefile for handling mojaloop bootstrap 
# Some code below is based on the projects at;
# https://github.com/paulRbr/terraform-makefile/blob/master/Makefile
# https://github.com/pgporada/terraform-makefile/blob/master/Makefile

.ONESHELL:
SHELL := bash
# .ONESHELL means errors in all but the last line are swallowed and will not cause a target to
# fail, add these flags to detect and crash on that failure
.SHELLFLAGS = -euo pipefail -c
.PHONY: config upgrade set-env backend tfvars plan apply init help

BOLD=$(shell tput bold)
RED=$(shell tput setaf 1)
GREEN=$(shell tput setaf 2)
YELLOW=$(shell tput setaf 3)
RESET=$(shell tput sgr0)

##
# TERRAFORM INSTALL
##
terraform_version  ?= 0.14.7
# Terraform ansible provider plugin, from https://github.com/nbering/terraform-provider-ansible/releases
tf-provider-ansible_version ?= 1.0.4
# Ansible dynamic inventory script to use with above provider plugin, from https://github.com/nbering/terraform-inventory/releases
tf-inventory_version ?= 2.2.0
os       ?= $(shell uname|tr A-Z a-z)
ifeq ($(shell uname -m),x86_64)
	arch   ?= amd64
endif
ifeq ($(shell uname -m),i686)
	arch   ?= 386
endif
ifeq ($(shell uname -m),aarch64)
	arch   ?= arm
endif

##
# INTERNAL VARIABLES
##
# Read all subsequent tasks as arguments of the first task
RUN_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
$(eval $(args) $(RUN_ARGS):;@:)
mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
mkfile_dir_full := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
mkfile_dir = $(mkfile_dir_full:/=)# trim the trailing slash

ansible-working-dir ?= ansible
terraform_path   := $(shell command -v terraform 2> /dev/null)
tf-provider_path := $(shell if [ -e ~/.terraform.d/plugins/terraform-provider-ansible* ]; then echo "Exists"; fi )
tf-working-dir ?= terraform/$(cloud_provider)
#wg-path:= docker run -i --rm --log-driver none -v /tmp:/tmp --cap-add NET_ADMIN --net host --name wg r.j3ss.co/wg
wg-path:= wg
ifndef tf-provider_path 
	install_tf-provider ?= "true"
endif
ifndef terraform_path
	install ?= "true"
endif

##
# Load the .env file if it exists
##
ifneq (,$(wildcard ./.env))
		include .env
		export
endif

ifdef onprem_ssh_user
  ssh_user=$(onprem_ssh_user)
else 
	ssh_user="ubuntu"
endif

##
# Assign defaults if they weren't loaded from the .env file
##
AWS_PROFILE?=default
cloud_provider?="aws"
project?="mojaloop"
environment?="k3s"
ingress_name?=nginx
monitoring_stack?=efk
master_instance_type?=m5.large
master_volume_size?=100
agent_volume_size?=100
agent_node_count?=3
agent_instance_type?=t3.large
region?=eu-west-1
wireguard_client_count?=4
AWS_REGION=$(region)
create_public_zone?=yes
create_private_zone?=yes
onprem_configure_haproxy?=no
letsencrypt_server?=production
vpc_cidr?=10.106.0.0/23
install_pm4ml_ml_simulator_cc?=yes
install_mojaloop?=yes
mojaloop_version?=10.6.0
install_pm4ml?=yes
install_sims?=no
sims_config_file?=/k3s-boot/ansible_sim_output.yaml
pm4ml_config_file?=/k3s-boot/samplefiles/pm4ml-config.yml
pm4ml_static_config_file?=/k3s-boot/samplefiles/pm4ml-static-config.yml
pm4ml_client_cert_remote_dir?=/tmp/client-certs/
pm4ml_client_cert_local_dir?=/k3s-boot/certoutput/
additional_ml_cc_values_file?=/k3s-boot/cc_values.yaml
pm4ml_helm_version?=2.0.0
pm4ml_dfsp_internal_access_only?=no
internal_pm4ml_instance?=no
k3s_version?=v1.21.2+k3s1
install_portainer?=no
##
# Configuration variables
##
S3_BUCKET=$(client)-$(project)-state
DYNAMODB_TABLE=$(client)-$(project)-lock
STATE_KEY=$(environment)/terraform.tfstate

base_domain=$(subst -,,$(client)).$(domain)
onprem_external_hostname?=$(base_domain)
onprem_bastion_host?=none
wg_dns=$(subst .0/23,,$(vpc_cidr)).2

# used in terraform steps to set TF_VAR's
tfvarset:= @export `sed -E 's/(.*)\=(.*)/TF_VAR_\1\="\\"\2\\""/' .env | xargs`; export AWS_PROFILE=$(AWS_PROFILE) 
#
# Markdown formatted content used by the doc target
#
define environment_markdown
# Environment configuration for $(client) - $(project)
## Configuration settings:
| Setting | Value |
|---------|-------|
| Client  | $(client) |
| Domain  | $(domain) |
| Project | $(project) |
| Environment | $(environment) |
| Cloud Provider | $(cloud_provider) |
| Cloud Region   | $(region) |
| Master instance type | $(master_instance_type) |
| Master volume size | $(master_volume_size) |
| Agent node count | $(agent_node_count) |
| Agent instance type | $(agent_instance_type) |
| Agent volume size | $(agent_volume_size) |
| Ingress controller | $(ingress_name) |
| Lets Encrypt account | $(letsencrypt_email) |
| Wireguard client count | $(wireguard_client_count) |


## Environment URLs
| Name | URL |
|------|-----|
| Grafana | (grafana.$(base_domain))
| Kibana  | (kibana.$(base_domain))
| Gitlab  | (gitlab.$(base_domain))
| Wireguard | (vpn.$(base_domain))

endef

#
# Template for wireguard profile, used in wireguard targets
#
define wg_profile
[Interface] 
PrivateKey = $$clientkey
Address = 192.168.100.$$clientIP/32
DNS = $(wg_dns)
[Peer]
PublicKey = $$serverkey
AllowedIPs = $(vpc_cidr)
Endpoint = $$vpn_endpoint:51820
PersistentKeepalive = 25
endef

#
# Template for haproxy config in onprem deployments
#
define onprem_haproxy_cfg
frontend http_front
	bind *:80
	bind *:443 ssl crt $${haproxy_cert_path}
	stats uri /haproxy?stats
	default_backend http_back

backend http_back
  option httpchk GET /healthz
	balance roundrobin
	$${haproxybackends}
endef

#
# Targets below here, ordered alphabetically
#

ambassador-admin-ui: ssh-key ## Open a local browser to connect to ambassador via an ssh tunnel and kubectl port-forward
	@export ANSIBLE_TF_DIR=$(tf-working-dir)
	@export PYTHONWARNINGS="ignore::DeprecationWarning" 
	echo "Once ssh tunnel is established, Open http://127.0.0.1:8877/ambassador/v0/diag/ to access ambassador admin interface. "
	make ssh-master SSH_COMMAND="-L 8877:127.0.0.1:8877 -t -- /usr/local/bin/kubectl --kubeconfig /home/$(ssh_user)/kubeconfig port-forward -n default service/ambassador-admin 8877:8877"

ansible/envvars.yml: .env
	@sed -E 's/(.*)\=(.*)/\1\: "\2"/' .env > $@

.ONESHELL:
ansible-playbook: ansible/envvars.yml ## Execute ansible playbook(s). Usage: make ansible-playbook -- playbookname.yml
ifeq ("$(RUN_ARGS)","")
	@echo "$(RED)[ERROR] No ansible playbook specified.$(RESET)"
	 echo "$(YELLOW)Specify the required playbook to run as extra arguments to make, e.g;"
	 echo "make ansible-playbook -- gitlab.yml"
	 echo "Available playbooks;"
	 ls -1 ansible/*.yml | cut -f 2 -d /
else 
	@cd $(ansible-working-dir)
	 export ANSIBLE_TF_DIR=../$(tf-working-dir)
	 export PYTHONWARNINGS="ignore::DeprecationWarning"
	 export ANSIBLE_HOST_KEY_CHECKING=False
	 ansible-playbook -vvv --ssh-common-args='-o StrictHostKeyChecking=no' -e "@envvars.yml" -e 'host_key_checking=False' -i inventory.yml -i terraform.py $(RUN_ARGS)
endif

ansible-debug-var: ansible/envvars.yml ## Debug an ansible variable. Usage: make ansible-playbook -- <varname>
ifeq ("$(RUN_ARGS)","")
	@echo "$(RED)[ERROR] No ansible variable specified.$(RESET)"
	 echo "$(YELLOW)Specify the variable to debug as extra arguments to make, e.g;"
	 echo "make ansible-debug-var -- varname"
else 
	@cd $(ansible-working-dir)
	 export ANSIBLE_TF_DIR=../$(tf-working-dir)
	 export PYTHONWARNINGS="ignore::DeprecationWarning"
	 export ANSIBLE_HOST_KEY_CHECKING=False
	 ansible -m debug -a "var=$(RUN_ARGS)" -i inventory.yml -e @envvars.yml -i terraform.py localhost
endif

ansible/terraform.py: 
	@curl --output ./ansible/terraform.py -L https://github.com/nbering/terraform-inventory/releases/download/v$(tf-inventory_version)/terraform.py
	@chmod 755 terraform.py && dos2unix terraform.py

.ONESHELL:
apply: install-terraform ## Execute a terraform apply
	$(tfvarset)
	cd $(tf-working-dir)
	$(terraform_path) apply $(RUN_ARGS)

backend: ## Prepare a new environment if needed, create the s3 and dynamodb backend and set the tfstate backend config
	echo "$(BOLD)Verifying that the S3 bucket $(S3_BUCKET) for remote state exists$(RESET)"
	@if ! aws --profile $(AWS_PROFILE) s3api head-bucket --region $(AWS_REGION) --bucket $(S3_BUCKET) > /dev/null 2>&1 ; then \
		echo "$(BOLD)S3 bucket $(S3_BUCKET) was not found, creating new bucket with versioning enabled to store tfstate$(RESET)"; \
	 	aws --profile $(AWS_PROFILE) s3api create-bucket \
	 		--bucket $(S3_BUCKET) \
	 		--acl private \
	 		--region $(AWS_REGION) \
	 		--create-bucket-configuration LocationConstraint=$(AWS_REGION)  2>&1 ; \
	 	aws --profile $(AWS_PROFILE) s3api put-bucket-versioning \
	 		--bucket $(S3_BUCKET) \
	 		--versioning-configuration Status=Enabled > /dev/null 2>&1 ; \
	 	echo "$(BOLD)$(GREEN)S3 bucket $(S3_BUCKET) created$(RESET)"; \
		else
	 	echo "$(BOLD)$(GREEN)S3 bucket $(S3_BUCKET) exists$(RESET)"; \
		fi
	@echo "$(BOLD)Verifying that the DynamoDB table exists for remote state locking$(RESET)"
	@if ! aws --profile $(AWS_PROFILE) dynamodb describe-table --table-name $(DYNAMODB_TABLE) > /dev/null 2>&1 ; then \
		echo "$(BOLD)DynamoDB table $(DYNAMODB_TABLE) was not found, creating new DynamoDB table to maintain locks$(RESET)"; \
		aws --profile $(AWS_PROFILE) dynamodb create-table \
					--region $(AWS_REGION) \
					--table-name $(DYNAMODB_TABLE) \
					--attribute-definitions AttributeName=LockID,AttributeType=S \
					--key-schema AttributeName=LockID,KeyType=HASH \
					--provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5  2>&1 ; \
		echo "$(BOLD)$(GREEN)DynamoDB table $(DYNAMODB_TABLE) created$(RESET)"; \
		echo "Sleeping for 10 seconds to allow DynamoDB state to propagate through AWS"; \
		sleep 10; \
	 else
		echo "$(BOLD)$(GREEN)DynamoDB Table $(DYNAMODB_TABLE) exists$(RESET)"; \
	 fi
	make init

config: .env ## Run first-time configuration
.ONESHELL:
.env:
# Convenience function to prompt user for input and/or assign a default
	@function readConfigVar { \
		value=""; \
		description=$$1
		name=$$2
		default=$$3
		while [[ -z $$value ]]; \
		do \
			read -p "$$description [$$default]:" input; \
			if [[ -z $$input ]] && [[ -z $$default ]]; then \
				echo "Value required for $$name"; \
			elif [[ -z $$input ]] && [[ -n $$default ]]; then \
				value=$$default; \
			elif [[ -n $$input ]]; then \
				value=$$input; \
			fi; \
		done; \
		echo "$$name=$${value}" >> $@; \
		echo "$${value}" \ 
	}
	if [[ -e .env ]]; then \
		mv .env .env.bak; \
	fi
# Read user input and/or assign default values for environment variables
# TODO: refactor some of the cloud provider specific variables when any provider other than AWS is added
	@client=$$(readConfigVar "Client" "client" "$(client)")
	domain=$$(readConfigVar "Domain" "domain" "$(domain)")
	project=$$(readConfigVar "Project" "project" "$(project)")
	environment=$$(readConfigVar "Environment" "environment" "$(environment)")
	cloud_provider=$$(readConfigVar "Cloud Provider (Only aws or onprem Supported at present)" "cloud_provider" "$(cloud_provider)")

	if [ $$cloud_provider = "onprem" ]; then
		onprem_master_hosts=$$(readConfigVar "Master Node IP:" "onprem_master_hosts" "$(onprem_master_hosts)")
		onprem_agent_hosts=$$(readConfigVar "Agent Node IPs (comma separated):" "onprem_agent_hosts" "$(onprem_agent_hosts)")
		onprem_bastion_host=$$(readConfigVar "Bastion Node IP [Enter 'none' for no bastion]):" "onprem_bastion_host" "$(onprem_bastion_host)")
		# If no bastion host was entered, set use_bastion to false
		if [ $$onprem_bastion_host = none ]; then use_bastion="false"; else use_bastion="true"; fi;
		echo "use_bastion=$${use_bastion}" >> $@;
		onprem_configure_haproxy=$$(readConfigVar "Configure haproxy load balancer pair? (yes|no)" "onprem_configure_haproxy" "$(onprem_configure_haproxy)")
		if [ $$onprem_configure_haproxy = "yes" ]; then 
			onprem_haproxy_primary=$$(readConfigVar "HAProxy Primary Server IP" "onprem_haproxy_primary" "$(onprem_haproxy_primary)")
			onprem_haproxy_secondary=$$(readConfigVar "HAProxy Secondary Server IP" "onprem_haproxy_secondary" "$(onprem_haproxy_secondary)")
			onprem_haproxy_virtual=$$(readConfigVar "HAProxy Virtual/Shared IP" "onprem_haproxy_virtual" "$(onprem_haproxy_virtual)")
			onprem_haproxy_cert=$$(readConfigVar "HAProxy SSL Cert Path" "onprem_haproxy_cert" "$(onprem_haproxy_cert)")
		else 
			onprem_haproxy_primary=""
			onprem_haproxy_secondary=""
			onprem_haproxy_virtual=""
			onprem_haproxy_cert=""
		fi;
		# ansible needs a variable with the number of nodes, so count the commas to get that number
		comma_count=$$onprem_agent_hosts | awk -F"," '{print NF-1}'
		agent_node_count=$$(expr $$comma_count + 1)
		echo "agent_node_count=$${agent_node_count}" >> $@;
		onprem_external_hostname=$$(readConfigVar "Externally accessible hostname/ip for ingress controller (leave empty to use base domain)" "onprem_external_hostname" "$(onprem_external_hostname)")
		onprem_ssh_user=$$(readConfigVar "Username for ansible to connect via SSH" "onprem_ssh_user" "$(onprem_ssh_user)")
		onprem_ssh_private_key=$$(readConfigVar "Absolute Path to SSH Key file for ansible to connect to nodes" "onprem_ssh_private_key" "$(onprem_ssh_private_key)")
	else 
		# bastion is always true for AWS
		echo "use_bastion=true" >> $@;
		region=$$(readConfigVar "Cloud Provider Region" "region" "$(region)")
		create_public_zone=$$(readConfigVar "Create Public DNS Zone (yes|no)" "create_public_zone" "$(create_public_zone)")
		create_private_zone=$$(readConfigVar "Create Private DNS Zone  (yes|no)" "create_private_zone" "$(create_private_zone)")
		master_instance_type=$$(readConfigVar "K3s Master instance type" "master_instance_type" "$(master_instance_type)")
		master_volume_size=$$(readConfigVar "K3s Master volume size (GB)" "master_volume_size" "$(master_volume_size)")
		agent_node_count=$$(readConfigVar "Number of k3s agent nodes" "agent_node_count" "$(agent_node_count)")
		agent_instance_type=$$(readConfigVar "K3s Agent instance type" "agent_instance_type" "$(agent_instance_type)")
		agent_volume_size=$$(readConfigVar "K3s Agent volume size (GB)" "agent_volume_size" "$(agent_volume_size)")
	fi
	install_portainer=$$(readConfigVar "Install portainer? (yes|no)" "install_portainer" "$(install_portainer)")
	ingress_name=$$(readConfigVar "Ingress controller (nginx or traefik or ambassador)" "ingress_name" "$(ingress_name)")
	monitoring_stack=$$(readConfigVar "Monitoring stack (efk or loki) [See README if unsure]" "monitoring_stack" "$(monitoring_stack)")
	letsencrypt_email=$$(readConfigVar "Lets Encrypt Account Email" "letsencrypt_email" "$(letsencrypt_email)")
	letsencrypt_server=$$(readConfigVar "Lets Encrypt Server (staging|production)" "letsencrypt_server" "$(letsencrypt_server)")
	wireguard_client_count=$$(readConfigVar "Number of wireguard vpn client keys to generate" "wireguard_client_count" "$(wireguard_client_count)")
	install_mojaloop=$$(readConfigVar "Install Mojaloop? (yes|no)" "install_mojaloop" "$(install_mojaloop)")
	install_pm4ml=$$(readConfigVar "Install PM4ML? (yes|no)" "install_pm4ml" "$(install_pm4ml)")
	install_sims=$$(readConfigVar "Install SIMS? (yes|no)" "install_sims" "$(install_sims)")

	if [ $$install_mojaloop = "yes" ]; then 
		mojaloop_version=$$(readConfigVar "Mojaloop version" "mojaloop_version" "$(mojaloop_version)")
	fi
	if [ $$install_pm4ml = "yes" ]; then 
		pm4ml_config_file=$$(readConfigVar "PM4ML Config File" "pm4ml_config_file" "$(pm4ml_config_file)")
		pm4ml_static_config_file=$$(readConfigVar "PM4ML Static Config File" "pm4ml_static_config_file" "$(pm4ml_static_config_file)")
		pm4ml_client_cert_remote_dir=$$(readConfigVar "PM4ML Remote Cert Dir" "pm4ml_client_cert_remote_dir" "$(pm4ml_client_cert_remote_dir)")
		pm4ml_client_cert_local_dir=$$(readConfigVar "PM4ML Local Cert Dir" "pm4ml_client_cert_local_dir" "$(pm4ml_client_cert_local_dir)")
		pm4ml_helm_version=$$(readConfigVar "PM4ML Chart Version" "pm4ml_helm_version" "$(pm4ml_helm_version)")
		pm4ml_dfsp_internal_access_only=$$(readConfigVar "PM4ML Endpoint Access" "pm4ml_dfsp_internal_access_only" "$(pm4ml_dfsp_internal_access_only)")
		internal_pm4ml_instance=$$(readConfigVar "expose outbound connector ingress" "internal_pm4ml_instance" "$(internal_pm4ml_instance)")
	fi
	if [ $$install_sims = "yes" ]; then 
		sims_config_file=$$(readConfigVar "SIMS Config File" "sims_config_file" "$(sims_config_file)")
	fi
	echo "Configuration complete"

.ONESHELL:
destroy: install-terraform tfvars ## Execute a terraform destroy
	$(tfvarset)
	cd $(tf-working-dir)
	$(terraform_path) destroy $(RUN_ARGS)

doc: environment.md ## Output a markdown formatted document with environment configuration information and URLs
environment.md:
	@echo "$(GREEN)Generating documentation in $@$(RESET)"
	@echo "$(environment_markdown)" > $@


.PHONY:
gitlab-login: ## Get initial login details for gitlab root user
	@encoded=$$(make -s ssh-master SSH_COMMAND="kubectl --kubeconfig /home/$(ssh_user)/kubeconfig get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}'")
	decoded=$$(echo $$encoded | base64 --decode)
	echo "Login to gitlab using:"
	echo "https://gitlab.$(project:-=).$(domain)"
	echo "Username: root"
	echo "Password: $$decoded"

gitlab: ssh-key ## Install gitlab, create a group, upload this repo to the newly created gitlab and configure the k3s server as a kubernetes deployment target in gitlab
	@make ansible-playbook -- gitlab.yml
	@echo Execute `make gitlab-login` to get root credentials for gitlab


grafana-ui: ssh-key grafana-login ## Open a local browser to connect to grafana via an ssh tunnel and kubectl port-forward
	@export ANSIBLE_TF_DIR=$(tf-working-dir) && \
	export PYTHONWARNINGS="ignore::DeprecationWarning" && \
	echo "Once ssh tunnel is established, Open http://127.0.0.1:8081 to access grafana"
	make ssh-master SSH_COMMAND="-L 8081:127.0.0.1:8081 -t -- /usr/local/bin/kubectl --kubeconfig /home/$(ssh_user)/kubeconfig port-forward -n monitoring service/grafana 8081:80"
  
.PHONY:
grafana-login: ssh-key ## Get initial login details for grafana admin user
	@if [ $(monitoring_stack) = 'loki' ]; then grafana_secret_name='loki-grafana'; else grafana_secret_name='grafana'; fi
	encoded=$$(make -s ssh-master SSH_COMMAND="/usr/local/bin/kubectl --kubeconfig /home/$(ssh_user)/kubeconfig get secret --namespace monitoring $$grafana_secret_name -o jsonpath='{.data.admin-password}'") && \
	decoded=$$(echo $$encoded | base64 --decode) && \
	echo "Login to grafana using:" && \
	echo "Username: admin" && \
	echo "Password: $$decoded"


init: install-terraform ## Initialise terraform with the backend config
	echo "$(BOLD)Configuring the terraform backend$(RESET)"
	cd $(tf-working-dir) && $(terraform_path) init \
	  -reconfigure \
		-input=false \
		-force-copy \
		-lock=true \
		-verify-plugins=true \
		-backend=true \
		-backend-config="profile=$(AWS_PROFILE)" \
		-backend-config="region=$(AWS_REGION)" \
		-backend-config="bucket=$(S3_BUCKET:\"=)" \
		-backend-config="key=$(STATE_KEY)" \
		-backend-config="encrypt=true" \
		-backend-config="dynamodb_table=$(DYNAMODB_TABLE:' '='')"\
		-backend-config="acl=private"


install-terraform: tf-provider-ansible ## Install terraform and the required ansible provider
ifeq ($(install),"true")
	@echo "$(GREEN)Installing terraform $(terraform_version) $(RESET)"; 
	@wget -O /tmp/terraform.zip https://releases.hashicorp.com/terraform/$(terraform_version)/terraform_$(terraform_version)_$(os)_$(arch).zip
	@unzip -d /usr/local/bin /tmp/terraform.zip && rm /tmp/terraform.zip
else 
	@echo "$(GREEN)Terraform $(terraform_version) is already installed $(RESET)";
endif

.ONESHELL:
k3s: ## Install k3s and deploy infrastructure components onto k3s cluster, terraform must be run prior
	@touch ssh-key && rm ssh-key && make ssh-key 
	@make ansible-playbook -- k3s.yml && make ansible-playbook -- k3s-infra.yml

kubeconfig: ## Retrieve the kubeconfig file for using kubectl locally (via VPN)
	@echo "$(GREEN)Retrieving kubeconfig$(RESET)"
	@export ANSIBLE_TF_DIR=$(tf-working-dir) && \
	export PYTHONWARNINGS="ignore::DeprecationWarning" && \
	if [[ "$${use_bastion}" = "true" ]]; then \
		sshcommand=$$(ansible-inventory -i $(ansible-working-dir)/inventory.yml -i $(ansible-working-dir)/terraform.py --list | jq -r '"scp -o StrictHostKeyChecking=no -i $(mkfile_dir)/ssh-key " + " -o \"proxycommand ssh -W %h:%p -i $(mkfile_dir)/ssh-key " + ._meta.hostvars[.bastion.hosts[0]].ansible_ssh_user + "@" + .bastion.hosts[0] + "\" " + ._meta.hostvars[.k3s_master.hosts[0]].ansible_ssh_user + "@" + .k3s_master.hosts[0]'); \
	else \
		sshcommand=$$(ansible-inventory -i $(ansible-working-dir)/inventory.yml -i $(ansible-working-dir)/terraform.py --list | jq -r '"scp -o StrictHostKeyChecking=no -i $(mkfile_dir)/ssh-key " + ._meta.hostvars[.k3s_master.hosts[0]].ansible_ssh_user + "@" + .k3s_master.hosts[0]')
	fi;
	eval $$sshcommand:/home/$(ssh_user)/kubeconfig ./kubeconfig

longhorn-ui: ssh-key ## Open a local browser to connect to longhorn via an ssh tunnel and kubectl port-forward
	@export ANSIBLE_TF_DIR=$(tf-working-dir)
	@export PYTHONWARNINGS="ignore::DeprecationWarning" 
	echo "Once ssh tunnel is established, Open http://127.0.0.1:8080 to access longhorn management interface"
	make ssh-master SSH_COMMAND="-L 8080:127.0.0.1:8080 -t -- /usr/local/bin/kubectl --kubeconfig /home/$(ssh_user)/kubeconfig port-forward -n longhorn-system service/longhorn-frontend 8080:80"


mojaloop: ## Install mojaloop using the helm chart via ansible
	@echo "$(GREEN)Installing mojaloop $(mojaloop_version)"
	make ansible-playbook -- mojaloop.yml

.ONESHELL:
monitoring: ssh-key ## Install monitoring stack from ansible/monitoring.
	@make ansible-playbook -- monitoring.yml
	@echo Monitoring stack deployed, Execute `make grafana-login` to get grafana credentials

onprem-haproxy: ## If onprem_configure_haproxy was set to yes during config, run ansible playbook to install and configure haproxy servers for onprem
	@if [[ "$(onprem_configure_haproxy)" = "yes" ]]; then \
		make ansible-playbook -- haproxy.yml; \
	else \
		echo "onprem haproxy is not configured, run 'make reconfigure' and enter the required information first."; \
	fi; 
	


onprem-haproxy-cfg: ## Output a frontend/backend config section for manual onprem haproxy configuration 
	@read -p "Path on haproxy server to SSL Cert:" haproxy_cert_path;
	
	haproxybackends=""; count=0; 
	# loop through the list of masters and create a backend server config line for haproxy
	onprem_master_hosts=$(onprem_master_hosts)
	for i in $${onprem_master_hosts//,/ }; do \
		haproxybackends+="\tserver master$$count $$i:443 check ssl verify none\r\n"; \
		count=$(($$count+1)); \
	done; 
	# loop through the list of agents and create a backend server config line for haproxy
	onprem_agent_hosts=$(onprem_agent_hosts)
	count=0;
	for i in $${onprem_agent_hosts//,/ }; do \
		haproxybackends+="\tserver agent$$count $$i:443 check ssl verify none\r\n"; \
		count=$(($$count+1)); \
	done;
	echo -e "$(onprem_haproxy_cfg)"

.ONESHELL:
plan: install-terraform tfvars ## Execute a terraform plan
	$(tfvarset)
	cd $(tf-working-dir)
	$(terraform_path) plan $(RUN_ARGS)

pm4ml: ## Install pm4ml using the helm chart via ansible
	@echo "$(GREEN)Installing pm4ml with $(pm4ml_config_file), $(pm4ml_static_config_file), $(pm4ml_client_cert_remote_dir), $(pm4ml_client_cert_local_dir), $(pm4ml_helm_version), $(pm4ml_dfsp_internal_access_only), and $(internal_pm4ml_instance)"
	make ansible-playbook -- pm4ml.yml
	make scp-master SRC_PATH=$(pm4ml_client_cert_remote_dir) DEST_PATH=$(pm4ml_client_cert_local_dir)

uninstall-pm4ml: ## uninstall pm4ml using helm
	@echo "$(GREEN)Uninstalling pm4ml"
	make ansible-playbook -- uninstall-pm4ml.yml
reconfigure: ## Re-run first-time configuration to change values as needed
	@make -B config

scp-bastion: ssh-key ## Copy files from the bastion via scp. Syntax: SRC_PATH=<remote path> DEST_PATH=<local path> make scp-bastion
	@export ANSIBLE_TF_DIR=$(tf-working-dir)
	@export PYTHONWARNINGS="ignore::DeprecationWarning" 
	if [[ "$${use_bastion}" = "true" ]]; then \
		scpcommand=$$(ansible-inventory -i $(ansible-working-dir)/inventory.yml -i $(ansible-working-dir)/terraform.py --list | jq -r '"scp -o StrictHostKeyChecking=no -i $(mkfile_dir)/ssh-key " + ._meta.hostvars[.bastion.hosts[0]].ansible_ssh_user + "@" + .bastion.hosts[0]'); \
		eval $$scpcommand:$(SRC_PATH) $(DEST_PATH)
	else \
		echo "Bastion is not enabled, unable to connect"; \
	fi; 

scp-master: ssh-key ## Copy files from the master via scp. Syntax: SRC_PATH=<remote path> DEST_PATH=<local path> make scp-master
	@export ANSIBLE_TF_DIR=$(tf-working-dir)
	@export PYTHONWARNINGS="ignore::DeprecationWarning" 
	if [[ "$${use_bastion}" = "true" ]]; then \
		scpcommand=$$(ansible-inventory -i $(ansible-working-dir)/inventory.yml -i $(ansible-working-dir)/terraform.py --list | jq -r '"scp -r -o StrictHostKeyChecking=no -i $(mkfile_dir)/ssh-key -o \"proxycommand ssh -W %h:%p -i $(mkfile_dir)/ssh-key " + ._meta.hostvars[.bastion.hosts[0]].ansible_ssh_user + "@" + .bastion.hosts[0] + "\" " + ._meta.hostvars[.k3s_master.hosts[0]].ansible_ssh_user + "@" + .k3s_master.hosts[0] '); \
	else \
		scpcommand=$$(ansible-inventory -i $(ansible-working-dir)/inventory.yml -i $(ansible-working-dir)/terraform.py --list | jq -r '"scp -r -o StrictHostKeyChecking=no -i $(mkfile_dir)/ssh-key " + ._meta.hostvars[.k3s_master.hosts[0]].ansible_ssh_user + "@" + .k3s_master.hosts[0]'); \
	fi;
	eval $$scpcommand:$(SRC_PATH) $(DEST_PATH)

sims: ## Install SIMS using the helm chart via ansible
	@echo "$(GREEN)Installing sims with $(sims_config_file)"
	make ansible-playbook -- simulator.yml

# TODO: There is too much repetition in the various ssh-* targets, can these be made more DRY?
ssh-agent-%: ssh-key ## Connect to a given k3s agent via ssh
	@export ANSIBLE_TF_DIR=$(tf-working-dir)
	export PYTHONWARNINGS="ignore::DeprecationWarning" 
	if [[ "$${use_bastion}" = "true" ]]; then \
		sshcommand=$$(ansible-inventory -i $(ansible-working-dir)/inventory.yml -i $(ansible-working-dir)/terraform.py --list | jq -r '"ssh -o StrictHostKeyChecking=no -i $(mkfile_dir)/ssh-key " + ._meta.hostvars[.k3s_node.hosts[$*]].ansible_ssh_user + "@" + .k3s_node.hosts[$*] + " -o \"proxycommand ssh -W %h:%p -i $(mkfile_dir)/ssh-key " + ._meta.hostvars[.bastion.hosts[0]].ansible_ssh_user + "@" + .bastion.hosts[0] + "\""'); \
	else \
		sshcommand=$$(ansible-inventory -i $(ansible-working-dir)/inventory.yml -i $(ansible-working-dir)/terraform.py --list | jq -r '"ssh -o StrictHostKeyChecking=no -i $(mkfile_dir)/ssh-key " + ._meta.hostvars[.k3s_node.hosts[$*]].ansible_ssh_user + "@" + .k3s_node.hosts[$*]'); \
	fi;
	eval $$sshcommand $(RUN_ARGS) $(SSH_COMMAND)


ssh-bastion: ssh-key ## Connect to the bastion server via ssh
	@export ANSIBLE_TF_DIR=$(tf-working-dir) && \
	export PYTHONWARNINGS="ignore::DeprecationWarning" && \
	
	if [[ "$${use_bastion}" = "true" ]]; then \
		sshcommand=$$(ansible-inventory -i $(ansible-working-dir)/inventory.yml -i $(ansible-working-dir)/terraform.py --list | jq -r '"ssh -o StrictHostKeyChecking=no -i $(mkfile_dir)/ssh-key " + ._meta.hostvars[.bastion.hosts[0]].ansible_ssh_user + "@" + .bastion.hosts[0]'); \
		eval $$sshcommand $(RUN_ARGS) $(SSH_COMMAND)
	else \
		echo "Bastion is not enabled, unable to connect"; \
	fi; 

ssh-key:
	@cd $(tf-working-dir) && $(terraform_path) output ssh_private_key > $(mkfile_dir)/ssh-key
	@chmod 600 $(mkfile_dir)/ssh-key

ssh-master: ssh-key ## Connect to the k3s master server via ssh
	@export ANSIBLE_TF_DIR=$(tf-working-dir)
	@export PYTHONWARNINGS="ignore::DeprecationWarning" 
	if [[ "$${use_bastion}" = "true" ]]; then \
		sshcommand=$$(ansible-inventory -i $(ansible-working-dir)/inventory.yml -i $(ansible-working-dir)/terraform.py --list | jq -r '"ssh -o StrictHostKeyChecking=no -i $(mkfile_dir)/ssh-key " + ._meta.hostvars[.k3s_master.hosts[0]].ansible_ssh_user + "@" + .k3s_master.hosts[0] + " -o \"proxycommand ssh -W %h:%p -i $(mkfile_dir)/ssh-key " + ._meta.hostvars[.bastion.hosts[0]].ansible_ssh_user + "@" + .bastion.hosts[0] + "\""'); \
	else \
		sshcommand=$$(ansible-inventory -i $(ansible-working-dir)/inventory.yml -i $(ansible-working-dir)/terraform.py --list | jq -r '"ssh -o StrictHostKeyChecking=no -i $(mkfile_dir)/ssh-key " + ._meta.hostvars[.k3s_master.hosts[0]].ansible_ssh_user + "@" + .k3s_master.hosts[0]'); \
	fi;
	eval $$sshcommand $(RUN_ARGS) $(SSH_COMMAND)
	
.ONESHELL:
tf: install-terraform ## Execute any terraform command, usage: make tf -- <tf command>
	$(tfvarset)
	cd $(tf-working-dir)
	$(terraform_path) $(RUN_ARGS)

tf-provider-ansible: ansible/terraform.py
ifeq ($(install_tf-provider),"true")
	@curl --output /tmp/terraform-provider-ansible.zip -L https://github.com/nbering/terraform-provider-ansible/releases/download/v$(tf-provider-ansible_version)/terraform-provider-ansible_$(tf-provider-ansible_version)_$(os)_$(arch).zip
	@mkdir -p ~/.terraform.d/plugins
	@unzip -o -d ~/.terraform.d/plugins/ /tmp/terraform-provider-ansible.zip && rm /tmp/terraform-provider-ansible.zip
else 
	@echo "$(GREEN)terraform-provider-ansible $(tf-provider-ansible_version) is already installed $(RESET)"
endif

vault: ## Install vault in the cluster
	@make ansible-playbook -- vault.yml

vault-ui: ssh-key ## Open a local browser to connect to vault via an ssh tunnel and kubectl port-forward
	@export ANSIBLE_TF_DIR=$(tf-working-dir)
	@export PYTHONWARNINGS="ignore::DeprecationWarning" 
	VAULT_ROOT_TOKEN=$$(cat vault-keys.json | jq -r ".root_token")
	echo "Once ssh tunnel is established, Open http://127.0.0.1:8200 to access vault management interface. Login with root token: $$VAULT_ROOT_TOKEN "
	make ssh-master SSH_COMMAND="-L 8200:127.0.0.1:8200 -t -- /usr/local/bin/kubectl --kubeconfig /home/$(ssh_user)/kubeconfig port-forward -n default service/vault-ui 8200:8200"


#
# Wireguard targets
#
vpn: wireguard ## Alias for wireguard target

wireguard.private.key:
	@echo "$(YELLOW)No wireguard private key found, generating one now.$(RESET)";\
	$(wg-path) genkey > $@; 

wireguard.public.key: wireguard.private.key
	@echo "$(GREEN)Generating wireguard public key$(RESET)";\
	cat wireguard.private.key | $(wg-path) pubkey > $@

wireguard.clients/client%.conf: ## Generate a single wireguard client profile, this can be used to add additional profiles after the initial deployment
	@$(wg-path) genkey > $@.private.key; \
	cat $@.private.key | $(wg-path) pubkey > $@.public.key;\
	clientkey=$$(cat $@.private.key);\
	clientIP=$$(expr $* + 1);\
	serverkey=$$(cat wireguard.public.key);\
	base_domain=$$(echo $(client) | sed s/-//g).$(domain);\
	vpn_endpoint=vpn.$$base_domain; \
  echo "$(wg_profile)" > $@


wireguard.clients: ## Generate $wireguard_client_count number of client profiles, will only work during initial set up, use above if you need to add additional clients
	@mkdir $@; \
	for i in $$(seq 1 $(wireguard_client_count)); do \
		echo "$(GREEN)Generating client profile $$i$(RESET)"; \
		make wireguard.clients/client$$i.conf
	done;

wireguard: wireguard.public.key ##wireguard.clients ## Deploy wireguard vpn into the cluster
	make ansible-playbook -- vpn.yml
	echo "$(GREEN)Wireguard has been deployed, use the profiles found in the wireguard.clients directory to connect$(RESET)"


## Any target with a comment beginning ## will be included in the help output, e.g:
help: ## Prints out this help message
	@printf "\033[32mk3s-bootstrap makefile\033[0m\n\n"
	@grep -E '^[a-zA-Z0-9_-]+:.*?##.*$$' Makefile | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
