import sys
from google.ads.googleads.client import GoogleAdsClient

CUSTOMER_ID = "4509379845"

def main(client, customer_id):
    ga_service = client.get_service("GoogleAdsService")
    query = """
        SELECT
          campaign.id,
          campaign.name,
          campaign.status,
          metrics.impressions,
          metrics.clicks,
          metrics.cost_micros,
          metrics.conversions
        FROM campaign
        WHERE campaign.status != 'REMOVED'
          AND metrics.impressions > 0
        ORDER BY metrics.impressions DESC
    """
    
    search_request = client.get_type("SearchGoogleAdsRequest")
    search_request.customer_id = customer_id
    search_request.query = query

    response = ga_service.search(request=search_request)
    
    print("Traffic Numbers (Google Ads API):")
    print("-" * 80)
    for row in response:
        cost = row.metrics.cost_micros / 1_000_000
        print(f"Campaign: {row.campaign.name} (ID: {row.campaign.id})")
        print(f"  Impressions: {row.metrics.impressions}")
        print(f"  Clicks:      {row.metrics.clicks}")
        print(f"  Cost:        ${cost:.2f}")
        print(f"  Conversions: {row.metrics.conversions}")
        print("-" * 80)

if __name__ == "__main__":
    try:
        googleads_client = GoogleAdsClient.load_from_storage("google_ads_automation_payload/google-ads.yaml")
        main(googleads_client, CUSTOMER_ID)
    except Exception as e:
        print(f"Error: {e}")
