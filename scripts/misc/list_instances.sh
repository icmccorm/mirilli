rm -f ./instances.csv
touch instances.csv
aws ec2 describe-instances --output text --filters "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].[PublicDnsName, InstanceId, InstanceType, ImageId, State.Name, PrivateIpAddress]' | tr '\t' ',' > $1
