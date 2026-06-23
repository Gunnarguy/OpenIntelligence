import sys
import uuid
import os
from google.ads.googleads.client import GoogleAdsClient
from google.ads.googleads.errors import GoogleAdsException

CUSTOMER_ID = "4509379845"
CAMPAIGN_ID = "23970700798"
FINAL_URL = "https://fascinaiting.me/"

def create_ad_group(client, customer_id, campaign_id):
    ad_group_service = client.get_service("AdGroupService")
    ad_group_op = client.get_type("AdGroupOperation")
    ad_group = ad_group_op.create
    ad_group.name = f"OpenIntelligence AI Search #{str(uuid.uuid4())[:6]}"
    ad_group.status = client.enums.AdGroupStatusEnum.ENABLED
    ad_group.campaign = client.get_service("CampaignService").campaign_path(customer_id, campaign_id)
    ad_group.type_ = client.enums.AdGroupTypeEnum.SEARCH_STANDARD
    
    # Optional: CPC Bid
    ad_group.cpc_bid_micros = 1000000  # $1.00
    
    response = ad_group_service.mutate_ad_groups(customer_id=customer_id, operations=[ad_group_op])
    ad_group_resource_name = response.results[0].resource_name
    print(f"Created Ad Group: {ad_group_resource_name}")
    return ad_group_resource_name

def create_keywords(client, customer_id, ad_group_resource_name):
    agc_service = client.get_service("AdGroupCriterionService")
    
    keywords = [
        {"text": "openintelligence", "match_type": client.enums.KeywordMatchTypeEnum.PHRASE},
        {"text": "ai assistant app", "match_type": client.enums.KeywordMatchTypeEnum.BROAD},
        {"text": "best ai app", "match_type": client.enums.KeywordMatchTypeEnum.EXACT},
        {"text": "ai chatbot for iphone", "match_type": client.enums.KeywordMatchTypeEnum.PHRASE},
        {"text": "artificial intelligence app", "match_type": client.enums.KeywordMatchTypeEnum.PHRASE},
        {"text": "ios ai assistant", "match_type": client.enums.KeywordMatchTypeEnum.EXACT},
    ]
    
    operations = []
    for kw in keywords:
        op = client.get_type("AdGroupCriterionOperation")
        criterion = op.create
        criterion.ad_group = ad_group_resource_name
        criterion.status = client.enums.AdGroupCriterionStatusEnum.ENABLED
        criterion.keyword.text = kw["text"]
        criterion.keyword.match_type = kw["match_type"]
        operations.append(op)
        
    response = agc_service.mutate_ad_group_criteria(customer_id=customer_id, operations=operations)
    for result in response.results:
        print(f"Created Keyword: {result.resource_name}")

def create_responsive_search_ad(client, customer_id, ad_group_resource_name):
    ad_group_ad_service = client.get_service("AdGroupAdService")
    ad_group_ad_op = client.get_type("AdGroupAdOperation")
    ad_group_ad = ad_group_ad_op.create
    ad_group_ad.ad_group = ad_group_resource_name
    ad_group_ad.status = client.enums.AdGroupAdStatusEnum.ENABLED
    
    ad = ad_group_ad.ad
    ad.final_urls.append(FINAL_URL)
    
    # Headlines
    headlines = [
        "OpenIntelligence iOS",
        "The Best AI Assistant",
        "Download on App Store",
        "Your Personal AI",
        "AI Powered Intelligence"
    ]
    for text in headlines:
        headline = client.get_type("AdTextAsset")
        headline.text = text
        ad.responsive_search_ad.headlines.append(headline)
        
    # Descriptions
    descriptions = [
        "The ultimate mobile AI assistant for your iPhone.",
        "Experience the next generation of AI right on your phone.",
        "OpenIntelligence helps you answer anything instantly.",
        "Download today and unleash the power of AI."
    ]
    for text in descriptions:
        desc = client.get_type("AdTextAsset")
        desc.text = text
        ad.responsive_search_ad.descriptions.append(desc)
        
    # Path 1 and 2
    ad.responsive_search_ad.path1 = "app"
    ad.responsive_search_ad.path2 = "download"

    response = ad_group_ad_service.mutate_ad_group_ads(customer_id=customer_id, operations=[ad_group_ad_op])
    print(f"Created Responsive Search Ad: {response.results[0].resource_name}")

def main(client, customer_id, campaign_id):
    print("Building OpenIntelligence_Core_V2 Architecture...")
    ad_group_resource_name = create_ad_group(client, customer_id, campaign_id)
    create_keywords(client, customer_id, ad_group_resource_name)
    create_responsive_search_ad(client, customer_id, ad_group_resource_name)
    print("Successfully populated OpenIntelligence_Core_V2!")

if __name__ == "__main__":
    try:
        googleads_client = GoogleAdsClient.load_from_storage("google_ads_automation_payload/google-ads.yaml")
        main(googleads_client, CUSTOMER_ID, CAMPAIGN_ID)
    except GoogleAdsException as ex:
        print(f"Google Ads API Error: {ex.error.code().name}")
        for error in ex.failure.errors:
            print(f" -> {error.message}")
            if hasattr(error, 'location'):
                path = ".".join([element.field_name for element in error.location.field_path_elements])
                print(f"    Location: {path}")
        sys.exit(1)
