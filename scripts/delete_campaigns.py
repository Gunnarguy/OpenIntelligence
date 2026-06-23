import sys
from google.ads.googleads.client import GoogleAdsClient

CUSTOMER_ID = "4509379845"
CAMPAIGNS_TO_DELETE = [
    "23961013815", # V4
    "23961026577", # V6
    "23966076443"  # V5
]

def main(client, customer_id):
    campaign_service = client.get_service("CampaignService")
    
    operations = []
    for camp_id in CAMPAIGNS_TO_DELETE:
        operation = client.get_type("CampaignOperation")
        operation.remove = campaign_service.campaign_path(customer_id, camp_id)
        operations.append(operation)
        
    print(f"Deleting {len(operations)} campaigns...")
    response = campaign_service.mutate_campaigns(customer_id=customer_id, operations=operations)
    
    for result in response.results:
        print(f"Successfully Removed Campaign: {result.resource_name}")

if __name__ == "__main__":
    try:
        googleads_client = GoogleAdsClient.load_from_storage("google_ads_automation_payload/google-ads.yaml")
        main(googleads_client, CUSTOMER_ID)
    except Exception as e:
        print(f"Error: {e}")
