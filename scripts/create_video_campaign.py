import sys
import uuid
from google.ads.googleads.client import GoogleAdsClient
from google.ads.googleads.errors import GoogleAdsException

CUSTOMER_ID = "4509379845"
BUDGET_AMOUNT_MICROS = 2000000 # $2.00 per day
YOUTUBE_VIDEO_IDS = ["FfhbrBuB68s", "SUxEpnLDY8A", "6EmJymIMOR4", "HQGIkXVI0pw"]

def create_youtube_asset(client, customer_id, video_id):
    asset_service = client.get_service("AssetService")
    asset_operation = client.get_type("AssetOperation")
    asset = asset_operation.create
    asset.name = f"OpenIntelligence Video {video_id} {str(uuid.uuid4())[:4]}"
    asset.type_ = client.enums.AssetTypeEnum.YOUTUBE_VIDEO
    asset.youtube_video_asset.youtube_video_id = video_id
    
    response = asset_service.mutate_assets(customer_id=customer_id, operations=[asset_operation])
    return response.results[0].resource_name

def main(client, customer_id):
    campaign_service = client.get_service("CampaignService")
    campaign_budget_service = client.get_service("CampaignBudgetService")
    ad_group_service = client.get_service("AdGroupService")
    ad_group_ad_service = client.get_service("AdGroupAdService")
    
    uid = str(uuid.uuid4())[:6]

    print("1. Creating Budget...")
    budget_operation = client.get_type("CampaignBudgetOperation")
    campaign_budget = budget_operation.create
    campaign_budget.name = f"OpenIntelligence_Video_Budget_{uid}"
    campaign_budget.delivery_method = client.enums.BudgetDeliveryMethodEnum.STANDARD
    campaign_budget.amount_micros = BUDGET_AMOUNT_MICROS
    
    budget_response = campaign_budget_service.mutate_campaign_budgets(customer_id=customer_id, operations=[budget_operation])
    budget_resource_name = budget_response.results[0].resource_name
    print(f"Created budget: {budget_resource_name}")

    print("2. Creating Video Campaign...")
    campaign_operation = client.get_type("CampaignOperation")
    campaign = campaign_operation.create
    campaign.name = f"OpenIntelligence_YouTube_Ads_{uid}"
    campaign.advertising_channel_type = client.enums.AdvertisingChannelTypeEnum.VIDEO
    campaign.status = client.enums.CampaignStatusEnum.PAUSED
    campaign.campaign_budget = budget_resource_name
    
    # Standard bidding for responsive video ads
    client.copy_from(campaign.manual_cpv, client.get_type("ManualCpv"))

    campaign_response = campaign_service.mutate_campaigns(customer_id=customer_id, operations=[campaign_operation])
    campaign_resource_name = campaign_response.results[0].resource_name
    print(f"Created Video Campaign: {campaign_resource_name}")

    print("3. Creating Ad Group...")
    ad_group_operation = client.get_type("AdGroupOperation")
    ad_group = ad_group_operation.create
    ad_group.name = f"OpenIntelligence_AdGroup_{uid}"
    ad_group.campaign = campaign_resource_name
    ad_group.status = client.enums.AdGroupStatusEnum.ENABLED
    ad_group.type_ = client.enums.AdGroupTypeEnum.VIDEO_RESPONSIVE
    ad_group.cpc_bid_micros = 50000  # $0.05 bid

    ad_group_response = ad_group_service.mutate_ad_groups(customer_id=customer_id, operations=[ad_group_operation])
    ad_group_resource_name = ad_group_response.results[0].resource_name
    print(f"Created Ad Group: {ad_group_resource_name}")

    print("4. Fetching YouTube Assets & Building Ads...")
    ad_operations = []

    for i, video_id in enumerate(YOUTUBE_VIDEO_IDS):
        print(f" -> Processing Video {video_id}...")
        try:
            video_asset_name = create_youtube_asset(client, customer_id, video_id)
        except GoogleAdsException as ex:
            print(f"    WARNING: Could not create asset for {video_id}. It may already exist. Skipping this ad.")
            for error in ex.failure.errors:
                print(f"      - {error.message}")
            continue

        ad_group_ad_operation = client.get_type("AdGroupAdOperation")
        ad_group_ad = ad_group_ad_operation.create
        ad_group_ad.ad_group = ad_group_resource_name
        ad_group_ad.status = client.enums.AdGroupAdStatusEnum.PAUSED
        
        ad = ad_group_ad.ad
        ad.final_urls.append("https://fascinaiting.me")
        
        # Build Video Responsive Ad
        video_ad = ad.video_responsive_ad
        
        # Link the YouTube Video Asset
        ad_video_asset = client.get_type("AdVideoAsset")
        ad_video_asset.asset = video_asset_name
        video_ad.videos.append(ad_video_asset)
        
        # Link Text Assets
        ad_text_headline = client.get_type("AdTextAsset")
        ad_text_headline.text = "OpenIntelligence iOS"
        video_ad.headlines.append(ad_text_headline)
        
        ad_text_long = client.get_type("AdTextAsset")
        ad_text_long.text = "Download OpenIntelligence on the App Store"
        video_ad.long_headlines.append(ad_text_long)
        
        ad_text_desc = client.get_type("AdTextAsset")
        ad_text_desc.text = "The ultimate AI assistant for your iPhone"
        video_ad.descriptions.append(ad_text_desc)
        
        # Call to Action
        ad_text_cta = client.get_type("AdTextAsset")
        ad_text_cta.text = "Download"
        video_ad.call_to_actions.append(ad_text_cta)
        
        # Business Name
        ad_text_biz = client.get_type("AdTextAsset")
        ad_text_biz.text = "Fascinaiting"
        video_ad.business_names.append(ad_text_biz)

        ad_operations.append(ad_group_ad_operation)

    if ad_operations:
        print("5. Pushing Video Ads to Google...")
        try:
            ad_group_ad_response = ad_group_ad_service.mutate_ad_group_ads(customer_id=customer_id, operations=ad_operations)
            for result in ad_group_ad_response.results:
                print(f"Created Video Ad: {result.resource_name}")
            print("\nSUCCESS! Your fully automated video campaign is live (paused for review).")
        except GoogleAdsException as ex:
            print("Failed to create ads:")
            for error in ex.failure.errors:
                print(f"\tDetails: {error.message}")
    else:
        print("No ads were generated.")

if __name__ == "__main__":
    try:
        googleads_client = GoogleAdsClient.load_from_storage("google_ads_automation_payload/google-ads.yaml")
        main(googleads_client, CUSTOMER_ID)
    except GoogleAdsException as ex:
        print(f"Request failed with status {ex.error.code().name} and includes the following errors:")
        for error in ex.failure.errors:
            print(f"\tError: {error.error_code.ErrorCode().name}")
            print(f"\tDetails: {error.message}")
        sys.exit(1)
    except Exception as e:
        print(f"System Error: {e}")
