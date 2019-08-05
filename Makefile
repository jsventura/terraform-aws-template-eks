OWNER   = opetech
PROJECT = eks
ENV     = demo

AWS_REGION = us-east-1
DNS_DOMAIN = seidorlab.com
DNS_API    = $(PROJECT).$(DNS_DOMAIN)

EKS_VERSION  = 1.13
WORKER_TYPE  = m5a.2xlarge
WORKER_PRICE = 0.22
WORKER_SIZE  = 3

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

# validacion de master y nodos
validation:
	@echo "Validando master"
	@kubectl get svc
	@echo "Validando Nodos"
	@kubectl get nodes

init:
	export AWS_DEFAULT_REGION="$(AWS_REGION)" && \
	cd terraform/ && terraform init

apply:
	export AWS_DEFAULT_REGION="$(AWS_REGION)" && \
	cd terraform/ && terraform apply \
	  -var 'owner=$(OWNER)' \
	  -var 'project=$(PROJECT)' \
	  -var 'env=$(ENV)' \
	  -var 'eks_version=$(EKS_VERSION)' \
	  -var 'instance_type=$(WORKER_TYPE)' \
	  -var 'spot_price=$(WORKER_PRICE)' \
	  -var 'desired_capacity=$(WORKER_SIZE)' \
	-auto-approve \
	-lock-timeout=300s

configs:
	@rm -rf ~/.kube/ && rm -rf tmp/aws-auth-cm.yaml && mkdir -p tmp/
	aws eks --region $(AWS_REGION) update-kubeconfig --name $(OWNER)-$(ENV)
	$(eval WORKER_ROLE = $(shell cd terraform/ && terraform output role))
	@cp scripts/aws-auth-cm.yaml tmp/aws-auth-cm.yaml && sed -i 's|WORKER_ROLE|$(WORKER_ROLE)|g' tmp/aws-auth-cm.yaml
	kubectl apply -f tmp/aws-auth-cm.yaml

addon-dashboard:
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta1/aio/deploy/recommended.yaml
	kubectl apply -f scripts/eks-admin-service-account.yaml
	@sh scripts/get.sh
	@echo "Dashboard instalado"

addon-metrics:
	@mkdir -p tmp/ && rm -rf tmp/metrics-server/
	@cd tmp/ && git clone https://github.com/kubernetes-incubator/metrics-server.git
	kubectl create -f tmp/metrics-server/deploy/1.8+/
	@echo "Metrics instalado"

addon-ingress:
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/mandatory.yaml
	kubectl apply -f scripts/service-l7.yaml
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/aws/patch-configmap-l7.yaml
	@echo "Ingress instalado"

demo:
	@mkdir -p tmp/ && cp -R service/cafe-ingress.yaml tmp/cafe-ingress.yaml && sed -i 's|DNS|$(DNS_API)|g' tmp/cafe-ingress.yaml
	kubectl create -f service/cafe-service.yaml
	kubectl create -f tmp/cafe-ingress.yaml

destroy:
	export AWS_DEFAULT_REGION="$(AWS_REGION)" && \
	cd terraform/ && terraform destroy \
	  -var 'owner=$(OWNER)' \
	  -var 'project=$(PROJECT)' \
	  -var 'env=$(ENV)' \
	  -var 'eks_version=$(EKS_VERSION)' \
	  -var 'instance_type=$(WORKER_TYPE)' \
	  -var 'spot_price=$(WORKER_PRICE)' \
	  -var 'desired_capacity=$(WORKER_SIZE)' \
	-auto-approve \
	-lock-timeout=300s