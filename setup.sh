#!/bin/bash

# Configuration Variables
ENDPOINT="http://localstack:4566"
REGION="us-east-1"
# Our strict FinOps tags required for the project
TAGS="Key=Team,Value=DevOps Key=Service,Value=WebApp Key=Environment,Value=Local Key=CostCenter,Value=CC-101"
BACKUP_TAG="Key=BackupPlan,Value=daily"

echo "Waiting for LocalStack to be fully ready..."
# This prevents the race condition where the script runs before LocalStack is awake
until aws --endpoint-url=$ENDPOINT sts get-caller-identity &> /dev/null; do
  echo "LocalStack unavailable - sleeping..."
  sleep 5
done
echo "LocalStack is up! Beginning Infrastructure Provisioning."

# -------------------------------------------------------------------
# 1. Networking (Using Default VPC for LocalStack)
# -------------------------------------------------------------------
echo "Fetching Default VPC and Subnets..."
VPC_ID=$(aws --endpoint-url=$ENDPOINT ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text)
SUBNET_1=$(aws --endpoint-url=$ENDPOINT ec2 describe-subnets --query 'Subnets[0].SubnetId' --output text)
SUBNET_2=$(aws --endpoint-url=$ENDPOINT ec2 describe-subnets --query 'Subnets[1].SubnetId' --output text)

# -------------------------------------------------------------------
# 2. ACM Certificate (For HTTPS)
# -------------------------------------------------------------------
echo "Provisioning ACM Certificate..."
CERT_ARN=$(aws --endpoint-url=$ENDPOINT acm request-certificate \
    --domain-name "app.local" \
    --tags $TAGS \
    --query 'CertificateArn' --output text)

# -------------------------------------------------------------------
# 3. Application Load Balancer (ALB) & Target Group
# -------------------------------------------------------------------
echo "Creating Target Group..."
TG_ARN=$(aws --endpoint-url=$ENDPOINT elbv2 create-target-group \
    --name my-app-tg \
    --protocol HTTP --port 8000 \
    --vpc-id $VPC_ID \
    --tags $TAGS \
    --query 'TargetGroups[0].TargetGroupArn' --output text)

echo "Creating Application Load Balancer..."
ALB_ARN=$(aws --endpoint-url=$ENDPOINT elbv2 create-load-balancer \
    --name my-app-alb \
    --subnets $SUBNET_1 $SUBNET_2 \
    --tags $TAGS \
    --query 'LoadBalancers[0].LoadBalancerArn' --output text)

echo "Creating HTTPS Listener (Port 443)..."
aws --endpoint-url=$ENDPOINT elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTPS --port 443 \
    --certificates CertificateArn=$CERT_ARN \
    --default-actions Type=forward,TargetGroupArn=$TG_ARN \
    --tags $TAGS > /dev/null

echo "Creating HTTP to HTTPS Redirect Listener (Port 80)..."
aws --endpoint-url=$ENDPOINT elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTP --port 80 \
    --default-actions Type=redirect,RedirectConfig="{Protocol=HTTPS,Port=443,StatusCode=HTTP_301}" \
    --tags $TAGS > /dev/null

# -------------------------------------------------------------------
# 4. EC2 Launch Template & Auto Scaling Group
# -------------------------------------------------------------------
echo "Creating EC2 Launch Template..."
# We attach the tags to the instances that will be launched, including the Backup tag
LAUNCH_TEMPLATE_DATA="{\"ImageId\":\"ami-0c55b159cbfafe1f0\",\"InstanceType\":\"t2.micro\",\"TagSpecifications\":[{\"ResourceType\":\"instance\",\"Tags\":[{\"Key\":\"Team\",\"Value\":\"DevOps\"},{\"Key\":\"Service\",\"Value\":\"WebApp\"},{\"Key\":\"Environment\",\"Value\":\"Local\"},{\"Key\":\"CostCenter\",\"Value\":\"CC-101\"},{\"Key\":\"BackupPlan\",\"Value\":\"daily\"}]}, {\"ResourceType\":\"volume\",\"Tags\":[{\"Key\":\"BackupPlan\",\"Value\":\"daily\"}]}]}"

aws --endpoint-url=$ENDPOINT ec2 create-launch-template \
    --launch-template-name my-app-lt \
    --launch-template-data "$LAUNCH_TEMPLATE_DATA" \
    --tag-specifications "ResourceType=launch-template,Tags=[{Key=Team,Value=DevOps},{Key=Service,Value=WebApp},{Key=Environment,Value=Local},{Key=CostCenter,Value=CC-101}]" > /dev/null

echo "Creating Auto Scaling Group..."
aws --endpoint-url=$ENDPOINT autoscaling create-auto-scaling-group \
    --auto-scaling-group-name my-app-asg \
    --launch-template LaunchTemplateName=my-app-lt,Version='$Latest' \
    --min-size 1 --max-size 3 --desired-capacity 1 \
    --vpc-zone-identifier "$SUBNET_1,$SUBNET_2" \
    --target-group-arns $TG_ARN \
    --tags "ResourceId=my-app-asg,ResourceType=auto-scaling-group,Key=Team,Value=DevOps,PropagateAtLaunch=true" "ResourceId=my-app-asg,ResourceType=auto-scaling-group,Key=Service,Value=WebApp,PropagateAtLaunch=true" "ResourceId=my-app-asg,ResourceType=auto-scaling-group,Key=Environment,Value=Local,PropagateAtLaunch=true" "ResourceId=my-app-asg,ResourceType=auto-scaling-group,Key=CostCenter,Value=CC-101,PropagateAtLaunch=true" > /dev/null

# -------------------------------------------------------------------
# 5. AWS Backup Plan (Disaster Recovery)
# -------------------------------------------------------------------
echo "Creating Backup Vaults..."
aws --endpoint-url=$ENDPOINT backup create-backup-vault --backup-vault-name primary-vault --backup-vault-tags '{"Team":"DevOps","Service":"WebApp","Environment":"Local","CostCenter":"CC-101"}' > /dev/null
aws --endpoint-url=$ENDPOINT backup create-backup-vault --backup-vault-name dr-vault-us-west-2 --backup-vault-tags '{"Team":"DevOps","Service":"WebApp","Environment":"Local","CostCenter":"CC-101"}' > /dev/null # Simulating cross-region vault

echo "Creating Backup Plan..."
BACKUP_PLAN_JSON="{\"BackupPlanName\":\"Daily-Backup-Plan\",\"Rules\":[{\"RuleName\":\"DailyBackup30Days\",\"TargetBackupVaultName\":\"primary-vault\",\"ScheduleExpression\":\"cron(0 5 * * ? *)\",\"Lifecycle\":{\"DeleteAfterDays\":30},\"CopyActions\":[{\"DestinationBackupVaultArn\":\"arn:aws:backup:us-west-2:000000000000:backup-vault:dr-vault-us-west-2\"}]}]}"
PLAN_ID=$(aws --endpoint-url=$ENDPOINT backup create-backup-plan \
    --backup-plan "$BACKUP_PLAN_JSON" \
    --backup-plan-tags '{"Team":"DevOps","Service":"WebApp","Environment":"Local","CostCenter":"CC-101"}' \
    --query 'BackupPlanId' --output text)

echo "Assigning Backup Plan to tagged resources..."
SELECTION_JSON="{\"SelectionName\":\"DailyBackupSelection\",\"IamRoleArn\":\"arn:aws:iam::000000000000:role/DummyRole\",\"ListOfTags\":[{\"ConditionType\":\"STRINGEQUALS\",\"ConditionKey\":\"BackupPlan\",\"ConditionValue\":\"daily\"}]}"
aws --endpoint-url=$ENDPOINT backup create-backup-selection \
    --backup-plan-id $PLAN_ID \
    --backup-selection "$SELECTION_JSON" > /dev/null

echo "Infrastructure Provisioning Complete!"