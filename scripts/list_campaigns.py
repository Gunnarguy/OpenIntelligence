import sys
from google.ads.googleads.client import GoogleAdsClient
from google.ads.googleads.errors import GoogleAdsException

CUSTOMER_ID = "4509379845"

def main(client, customer_id):
    ga_service = client.get_service("GoogleAdsService")
    query = """
        SELECT
          campaign.id,
          campaign.name,
          campaign.status,
          campaign_budget.name
        FROM campaign
        WHERE campaign.name LIKE 'OpenIntelligence%'
          AND campaign.status != 'REMOVED'
    """
    
    search_request = client.get_type("SearchGoogleAdsRequest")
    search_request.customer_id = customer_id
    search_request.query = query

    response = ga_service.search(request=search_request)
    
    print("Found Campaigns:")
    for row in response:
        print(f"ID: {row.campaign.id} | Name: {row.campaign.name} | Status: {row.campaign.status.name} | Budget: {row.campaign_budget.name}")

if __name__ == "__main__":
    try:
        googleads_client = GoogleAdsClient.load_from_storage("google_ads_automation_payload/google-ads.yaml")
        main(googleads_client, CUSTOMER_ID)
    except Exception as e:
        print(f"Error: {e}")
