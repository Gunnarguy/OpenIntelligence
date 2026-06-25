import sys
from google.ads.googleads.client import GoogleAdsClient

CUSTOMER_ID = "4509379845"
CAMPAIGN_ID = "23970700798"

def main(client, customer_id, campaign_id):
    ga_service = client.get_service("GoogleAdsService")
    query = f"""
        SELECT campaign.id, campaign.name, campaign.advertising_channel_type
        FROM campaign
        WHERE campaign.id = {campaign_id}
    """
    response = ga_service.search(customer_id=customer_id, query=query)
    for row in response:
        print(f"ID: {row.campaign.id}")
        print(f"Name: {row.campaign.name}")
        print(f"Channel Type: {row.campaign.advertising_channel_type.name}")

if __name__ == "__main__":
    client = GoogleAdsClient.load_from_storage("google_ads_automation_payload/google-ads.yaml")
    main(client, CUSTOMER_ID, CAMPAIGN_ID)
