#!/bin/bash

DNS_DOMAIN=$1
AWS_REGION=$2
OWNER=$3
ENV=$4

aws elb describe-load-balancers --region ${AWS_REGION} --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text > list.tmp

while read line
do
    ELB_CHECK=`aws elb describe-tags --region ${AWS_REGION} --load-balancer-name ${line} | grep ${OWNER}-${ENV} | wc -l`
    if [ ${ELB_CHECK} -gt 0 ]; then
        ELB_DNS=`aws elb describe-load-balancers --region ${AWS_REGION} --load-balancer-name ${line} --query 'LoadBalancerDescriptions[].CanonicalHostedZoneName' --output text`
        ELB_ZONE=`aws elb describe-load-balancers --region ${AWS_REGION} --load-balancer-name ${line} --query 'LoadBalancerDescriptions[].CanonicalHostedZoneNameID' --output text`
        sed -i 's/ELB_DNS/'${ELB_DNS}'/g' ingress/dns.json
        sed -i 's/ELB_ZONE/'${ELB_ZONE}'/g' ingress/dns.json
        ZONE_ID=`aws route53 --region ${AWS_REGION} list-hosted-zones --output text | grep ${DNS_DOMAIN} | awk '{print $3}' | cut -d '/' -f3`
        aws route53 change-resource-record-sets --region ${AWS_REGION} --hosted-zone-id ${ZONE_ID} --change-batch file://ingress/dns.json
    fi
done <  list.tmp
