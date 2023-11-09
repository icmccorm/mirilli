rm -f ./instances.csv
touch instances.csv
aws ec2 describe-instances --output text --filters "Name=tag:Name,Values=eval-zero-update" --query 'Reservations[*].Instances[*].[PublicDnsName, InstanceId, InstanceType, ImageId, State.Name, PrivateIpAddress]' | tr '\t' ',' > $1
