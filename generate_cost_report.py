import boto3
import csv

def generate_report():
    print("Connecting to LocalStack and fetching tagged resources...")
    
    # Initialize the boto3 client to talk to our local sandbox
    client = boto3.client(
        'resourcegroupstaggingapi',
        endpoint_url='http://localhost:4566',
        region_name='us-east-1',
        aws_access_key_id='test',
        aws_secret_access_key='test'
    )

    try:
        # THE FIX: We added the 'Values' array to satisfy LocalStack's strict API requirements
        response = client.get_resources(
            TagFilters=[{
                'Key': 'CostCenter',
                'Values': ['CC-101'] 
            }]
        )
    except Exception as e:
        print(f"Error connecting to LocalStack: {e}")
        return

    resources = response.get('ResourceTagMappingList', [])
    
    if not resources:
        print("No tagged resources found. Make sure the setup script ran successfully!")
        return

    csv_filename = 'cost_report.csv'
    
    # Open the CSV file and write the required headers
    with open(csv_filename, mode='w', newline='') as file:
        writer = csv.writer(file)
        writer.writerow(['Service', 'ResourceType', 'ResourceID', 'CostCenter', 'Team'])
        
        # Loop through everything AWS found and extract the data
        for resource in resources:
            arn = resource['ResourceARN']
            tags = {tag['Key']: tag['Value'] for tag in resource['Tags']}
            
            # Parse the AWS ARN string to figure out what the resource actually is
            arn_parts = arn.split(':')
            service = arn_parts[2]
            resource_string = arn_parts[5] if len(arn_parts) > 5 else 'unknown'
            
            if '/' in resource_string:
                res_type, res_id = resource_string.split('/', 1)
            else:
                res_type = 'resource'
                res_id = resource_string
            
            cost_center = tags.get('CostCenter', 'Unknown')
            team = tags.get('Team', 'Unknown')
            
            # Write the row to our spreadsheet
            writer.writerow([service, res_type, res_id, cost_center, team])
            print(f"Logged {service} resource: {res_id} (Team: {team})")
            
    print(f"\n✅ Success! Finance report generated and saved to: {csv_filename}")

if __name__ == '__main__':
    generate_report()