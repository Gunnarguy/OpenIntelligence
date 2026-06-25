import sys
from google.ads.googleads.client import GoogleAdsClient

CUSTOMER_ID = "4509379845"

def main(client, customer_id):
    ga_service = client.get_service("GoogleAdsService")
    query = """
        SELECT
          campaign.id,
          campaign.name,
          ad_group_ad.ad.responsive_search_ad.headlines,
          ad_group_ad.ad.responsive_search_ad.descriptions
        FROM ad_group_ad
        WHERE campaign.advertising_channel_type = 'SEARCH'
          AND campaign.status != 'REMOVED'
          AND ad_group_ad.status != 'REMOVED'
    """
    
    search_request = client.get_type("SearchGoogleAdsRequest")
    search_request.customer_id = customer_id
    search_request.query = query

    response = ga_service.search(request=search_request)
    
    print("Search Campaign Ads Details:")
    for row in response:
        print(f"\nCampaign: {row.campaign.name} (ID: {row.campaign.id})")
        print("Headlines:")
        for headline in row.ad_group_ad.ad.responsive_search_ad.headlines:
            print(f" - {headline.text}")
        print("Descriptions:")
        for description in row.ad_group_ad.ad.responsive_search_ad.descriptions:
            print(f" - {description.text}")

if __name__ == "__main__":
    try:
        googleads_client = GoogleAdsClient.load_from_storage("google_ads_automation_payload/google-ads.yaml")
        main(googleads_client, CUSTOMER_ID)
    except Exception as e:
        print(f"Error: {e}")
