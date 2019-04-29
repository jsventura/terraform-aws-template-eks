OWNER   = punkerside
PROJECT = eks
ENV     = lab

AWS_REGION = us-east-1
DNS_DOMAIN = punkerside.com
DNS_API    = $(PROJECT).punkerside.com

WORKER_TYPE  = m5.large
WORKER_PRICE = 0.045
WORKER_SIZE  = 1

quickstart:
	@make init
	@make apply
	@make configs
	@make gui
	@make ingress-nginx
	@make dns
	@make demo

delete:
	@make destroy
	@make elb
	@make tmps

init:
	export AWS_DEFAULT_REGION="$(AWS_REGION)" && \
	cd terraform/ && \
	terraform init \
	  -backend-config bucket='$(OWNER)-prod-terraform' \
	  -backend-config key='state/$(PROJECT)/$(ENV)/terraform.tfstate' \
	  -backend-config region='us-east-1'

apply:
	export AWS_DEFAULT_REGION="$(AWS_REGION)" && \
	cd terraform/ && \
	terraform apply \
	  -var 'owner=$(OWNER)' \
	  -var 'project=$(PROJECT)' \
	  -var 'env=$(ENV)' \
	  -var 'region=$(AWS_REGION)' \
	  -var 'instance_type=$(WORKER_TYPE)' \
	  -var 'spot_price=$(WORKER_PRICE)' \
	  -var 'desired_capacity=$(WORKER_SIZE)' \
	-auto-approve \
	-lock-timeout=60s

destroy:
	export AWS_DEFAULT_REGION="$(AWS_REGION)" && \
	cd terraform/ && \
	terraform destroy \
	  -var 'owner=$(OWNER)' \
	  -var 'project=$(PROJECT)' \
	  -var 'env=$(ENV)' \
	  -var 'region=$(AWS_REGION)' \
	  -var 'instance_type=$(WORKER_TYPE)' \
	  -var 'spot_price=$(WORKER_PRICE)' \
	  -var 'desired_capacity=$(WORKER_SIZE)' \
	-auto-approve \
	-lock-timeout=60s

validate:
	export AWS_DEFAULT_REGION="$(AWS_REGION)" && \
	cd terraform/ && \
	terraform validate -check-variables=true \
	  -var 'owner=$(OWNER)' \
	  -var 'project=$(PROJECT)' \
	  -var 'env=$(ENV)' \
	  -var 'region=$(AWS_REGION)' \
	  -var 'instance_type=$(WORKER_TYPE)' \
	  -var 'spot_price=$(WORKER_PRICE)' \
	  -var 'desired_capacity=$(WORKER_SIZE)'

configs:
	@rm -rf ~/.kube/ && rm -rf workers/aws-auth-cm.yaml
	aws eks --region $(AWS_REGION) update-kubeconfig --name $(OWNER)-$(ENV)
	$(eval WORKER_ROLE = $(shell cd terraform/ && terraform output role))
	@cp workers/aws-auth-cm.yaml.original workers/aws-auth-cm.yaml && sed -i 's|WORKER_ROLE|$(WORKER_ROLE)|g' workers/aws-auth-cm.yaml
	kubectl apply -f workers/aws-auth-cm.yaml

gui:
	@rm -rf tmp/
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended/kubernetes-dashboard.yaml
	kubectl apply -f dashboard/eks-admin-service-account.yaml && ./dashboard/get.sh
	@mkdir tmp/ && cd tmp/ && git clone https://github.com/kubernetes-incubator/metrics-server.git
	kubectl create -f tmp/metrics-server/deploy/1.8+/

ingress-nginx:
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/mandatory.yaml
	kubectl apply -f ingress/service-l7.yaml
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/provider/aws/patch-configmap-l7.yaml

dns:
	@rm -rf ingress/dns.json && cp -R ingress/dns.original ingress/dns.json
	@sed -i 's|DNS_API|$(DNS_API)|g' ingress/dns.json
	@sh ingress/config.sh $(DNS_DOMAIN) $(AWS_REGION) $(OWNER) $(ENV)

demo:
	cp -R service/cafe-ingress.yaml.original service/cafe-ingress.yaml && sed -i 's|DNS_API|$(DNS_API)|g' service/cafe-ingress.yaml
	kubectl create -f service/

update:
	export AWS_DEFAULT_REGION="$(AWS_REGION)" && \
	cd terraform/ && \
	terraform get -update

tmps:
	$(eval ELB_NAME = $(shell cat list.tmp))
	aws elb delete-load-balancer --region $(AWS_REGION) --load-balancer-name $(ELB_NAME)
	@sed -i 's|CREATE|DELETE|g' ingress/dns.json
	$(eval ZONE_ID = $(shell aws route53 --region us-east-1 list-hosted-zones-by-name --dns-name $(DNS_DOMAIN) --query 'HostedZones[*].[Id]' --output text | cut -d'/' -f3))
	aws route53 change-resource-record-sets --region $(AWS_REGION) --hosted-zone-id $(ZONE_ID) --change-batch file://ingress/dns.json
	@rm -rf terraform/.terraform/
	@rm -rf tmp/
	@rm -rf ingress/dns.json
	@rm -rf list.tmp