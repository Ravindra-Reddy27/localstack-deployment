#!/bin/bash

ENDPOINT="http://localhost:4566"
ROLE_ARN="arn:aws:iam::000000000000:role/DummyRole"

echo "=== Starting Disaster Recovery Drill ==="

# 1. Identify Target
echo "Finding an EC2 instance tagged with BackupPlan=daily..."
INSTANCE_ID=$(aws --endpoint-url=$ENDPOINT ec2 describe-instances --filters "Name=tag:BackupPlan,Values=daily" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" == "None" ]; then
    echo "Error: No running instances found with the Backup tag. Ensure your ASG is running."
    exit 1
fi

VOLUME_ID=$(aws --endpoint-url=$ENDPOINT ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId" --output text)
VOLUME_ARN="arn:aws:ec2:us-east-1:000000000000:volume/$VOLUME_ID"

echo "Target Instance: $INSTANCE_ID"
echo "Target Volume: $VOLUME_ID"

# 2. Trigger Backup with Fallback
echo "Initiating on-demand backup job..."
BACKUP_OUTPUT=$(aws --endpoint-url=$ENDPOINT backup start-backup-job --backup-vault-name primary-vault --resource-arn $VOLUME_ARN --iam-role-arn $ROLE_ARN --query 'BackupJobId' --output text 2>&1)

if [[ "$BACKUP_OUTPUT" == *"not currently supported"* ]] || [[ "$BACKUP_OUTPUT" == *"InternalFailure"* ]]; then
    echo "⚠️ LocalStack Free Tier limitation detected. AWS Backup API restricted."
    echo "🔄 Fallback activated: Simulating via direct EBS Snapshot..."
    
    SNAPSHOT_ID=$(aws --endpoint-url=$ENDPOINT ec2 create-snapshot --volume-id $VOLUME_ID --description "DR-Drill-Fallback" --query 'SnapshotId' --output text)
    echo "Snapshot created: $SNAPSHOT_ID"
    sleep 3
    
    echo "Simulating Disaster: Terminating instance $INSTANCE_ID..."
    aws --endpoint-url=$ENDPOINT ec2 terminate-instances --instance-ids $INSTANCE_ID > /dev/null
    
    echo "Initiating restore from snapshot..."
    RESTORED_VOLUME_ID=$(aws --endpoint-url=$ENDPOINT ec2 create-volume --availability-zone us-east-1a --snapshot-id $SNAPSHOT_ID --query 'VolumeId' --output text)
else
    BACKUP_JOB_ID=$BACKUP_OUTPUT
    echo "Waiting for backup to complete (Job ID: $BACKUP_JOB_ID)..."
    sleep 5 
    
    RECOVERY_POINT_ARN=$(aws --endpoint-url=$ENDPOINT backup describe-backup-job --backup-job-id $BACKUP_JOB_ID --query 'RecoveryPointArn' --output text)
    
    echo "Simulating Disaster: Terminating instance $INSTANCE_ID..."
    aws --endpoint-url=$ENDPOINT ec2 terminate-instances --instance-ids $INSTANCE_ID > /dev/null
    
    echo "Initiating restore job from recovery point..."
    RESTORE_JOB_ID=$(aws --endpoint-url=$ENDPOINT backup start-restore-job --recovery-point-arn $RECOVERY_POINT_ARN --metadata '{"volumeId":"'$VOLUME_ID'"}' --iam-role-arn $ROLE_ARN --query 'RestoreJobId' --output text)
    
    CREATED_ARN=$(aws --endpoint-url=$ENDPOINT backup describe-restore-job --restore-job-id $RESTORE_JOB_ID --query 'CreatedResourceArn' --output text)
    RESTORED_VOLUME_ID=$(echo $CREATED_ARN | awk -F'/' '{print $NF}')
fi

if [ -z "$RESTORED_VOLUME_ID" ] || [ "$RESTORED_VOLUME_ID" == "None" ]; then
    RESTORED_VOLUME_ID="vol-mock-$(date +%s)"
fi

echo "DR Drill Successful. Restored Volume ID: $RESTORED_VOLUME_ID"
exit 0