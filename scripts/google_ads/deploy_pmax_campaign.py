import sys
import uuid
import os
from google.ads.googleads.client import GoogleAdsClient
from google.ads.googleads.errors import GoogleAdsException

CUSTOMER_ID = "4509379845"
BUDGET_AMOUNT_MICROS = 5000000 # $5.00/day
YOUTUBE_VIDEO_IDS = ["FfhbrBuB68s", "SUxEpnLDY8A", "6EmJymIMOR4"]
FINAL_URL = "https://fascinaiting.me"
ASSET_DIR = "google_ads_automation_payload/pmax_assets"

def upload_image_asset(client, customer_id, file_path, asset_name):
    with open(file_path, "rb") as f:
        image_data = f.read()
    asset_service = client.get_service("AssetService")
    asset_operation = client.get_type("AssetOperation")
    asset = asset_operation.create
    asset.name = asset_name
    asset.type_ = client.enums.AssetTypeEnum.IMAGE
    asset.image_asset.data = image_data
    response = asset_service.mutate_assets(customer_id=customer_id, operations=[asset_operation])
    return response.results[0].resource_name

def upload_youtube_asset(client, customer_id, video_id):
    asset_service = client.get_service("AssetService")
    asset_operation = client.get_type("AssetOperation")
    asset = asset_operation.create
    asset.name = f"OpenIntelligence Video {video_id} {str(uuid.uuid4())[:4]}"
    asset.type_ = client.enums.AssetTypeEnum.YOUTUBE_VIDEO
    asset.youtube_video_asset.youtube_video_id = video_id
    response = asset_service.mutate_assets(customer_id=customer_id, operations=[asset_operation])
    return response.results[0].resource_name

def upload_text_asset(client, customer_id, text):
    asset_service = client.get_service("AssetService")
    asset_operation = client.get_type("AssetOperation")
    asset = asset_operation.create
    asset.text_asset.text = text
    response = asset_service.mutate_assets(customer_id=customer_id, operations=[asset_operation])
    return response.results[0].resource_name

def create_asset_group_asset_op(client, ag_resource_name, asset_name, field_type_enum):
    mutate_op = client.get_type("MutateOperation")
    aga = mutate_op.asset_group_asset_operation.create
    aga.asset_group = ag_resource_name
    aga.asset = asset_name
    aga.field_type = field_type_enum
    return mutate_op

def create_campaign_asset_op(client, campaign_resource_name, asset_name, field_type_enum):
    mutate_op = client.get_type("MutateOperation")
    ca = mutate_op.campaign_asset_operation.create
    ca.campaign = campaign_resource_name
    ca.asset = asset_name
    ca.field_type = field_type_enum
    return mutate_op

def main(client, customer_id):
    uid = str(uuid.uuid4())[:6]
    print(f"Deploying Universal Performance Max Campaign [{uid}]...")
    
    print("1. Uploading Binary Image Assets...")
    logo_asset = upload_image_asset(client, customer_id, os.path.join(ASSET_DIR, "logo_1x1.png"), f"PMax Logo {uid}")
    landscape_asset = upload_image_asset(client, customer_id, os.path.join(ASSET_DIR, "landscape_191x1.png"), f"PMax Landscape {uid}")
    square_asset = upload_image_asset(client, customer_id, os.path.join(ASSET_DIR, "square_1x1.png"), f"PMax Square {uid}")
    portrait_asset = upload_image_asset(client, customer_id, os.path.join(ASSET_DIR, "portrait_4x5.png"), f"PMax Portrait {uid}")
    
    print("2. Mapping YouTube Video Assets...")
    video_assets = []
    for vid in YOUTUBE_VIDEO_IDS:
        try:
            v_asset = upload_youtube_asset(client, customer_id, vid)
            video_assets.append(v_asset)
        except Exception:
            pass
    
    print("3. Generating Text Assets...")
    headline_assets = [
        upload_text_asset(client, customer_id, "Privacy-First RAG Pipeline"),
        upload_text_asset(client, customer_id, "Apple Foundation Models"),
        upload_text_asset(client, customer_id, "Local-First Document AI"),
        upload_text_asset(client, customer_id, "On-Device AI Document Query"),
        upload_text_asset(client, customer_id, "Chat With Any Document"),
        upload_text_asset(client, customer_id, "Local 3B-Parameter AFM"),
        upload_text_asset(client, customer_id, "SQLite FTS5 Hybrid Search"),
        upload_text_asset(client, customer_id, "29-Step RAG Architecture"),
        upload_text_asset(client, customer_id, "Private Cloud Compute Ready"),
        upload_text_asset(client, customer_id, "Semantic Document Chunking"),
        upload_text_asset(client, customer_id, "Zero-Dependency Metal RAG"),
        upload_text_asset(client, customer_id, "Cross-Encoder Reranking"),
        upload_text_asset(client, customer_id, "Vision OCR Ingestion"),
        upload_text_asset(client, customer_id, "Lexical & Vector Search"),
        upload_text_asset(client, customer_id, "On-Device Inference iOS 26")
    ]
    long_headline_assets = [
        upload_text_asset(client, customer_id, "Experience an entirely on-device RAG pipeline built natively for Apple platforms."),
        upload_text_asset(client, customer_id, "Ingest documents with Vision OCR and query them locally via Apple Foundation Models."),
        upload_text_asset(client, customer_id, "Zero-dependency RAG engine using 384-dim MiniLM vectors and BNNS acceleration."),
        upload_text_asset(client, customer_id, "Execute a rigorous 29-step RAG pipeline securely on your iPhone without the cloud."),
        upload_text_asset(client, customer_id, "A production-grade iOS AI workspace with hybrid retrieval and cross-encoder reranking.")
    ]
    desc_assets = [
        upload_text_asset(client, customer_id, "Zero-dependency RAG engine using local BNNS vectors and SQLite FTS5 hybrid retrieval."),
        upload_text_asset(client, customer_id, "Run production-grade AI on your iPhone or Mac without sacrificing your data privacy."),
        upload_text_asset(client, customer_id, "Extract insights using local Vision OCR and generate grounded answers with citations."),
        upload_text_asset(client, customer_id, "Leverage Apple's 4K-token local context windows for deep semantic document search."),
        upload_text_asset(client, customer_id, "Features semantic chunking, Reciprocal Rank Fusion, and Platt-calibrated confidence.")
    ]
    biz_name_asset = upload_text_asset(client, customer_id, "Fascinaiting")

    print("4. Building Massive Atomic Google Ads Payload...")
    mutate_operations = []
    google_ads_service = client.get_service("GoogleAdsService")
    
    # Temp IDs
    budget_temp_id = f"customers/{customer_id}/campaignBudgets/-1"
    campaign_temp_id = f"customers/{customer_id}/campaigns/-2"
    ag_temp_id = f"customers/{customer_id}/assetGroups/-3"

    # BUDGET
    budget_op = client.get_type("MutateOperation")
    cb = budget_op.campaign_budget_operation.create
    cb.resource_name = budget_temp_id
    cb.name = f"OpenIntelligence_PMax_Budget_{uid}"
    cb.amount_micros = BUDGET_AMOUNT_MICROS
    cb.delivery_method = client.enums.BudgetDeliveryMethodEnum.STANDARD
    cb.explicitly_shared = False
    mutate_operations.append(budget_op)

    # CAMPAIGN
    campaign_op = client.get_type("MutateOperation")
    c = campaign_op.campaign_operation.create
    c.resource_name = campaign_temp_id
    c.name = f"OpenIntelligence_Universal_PMax_{uid}"
    c.advertising_channel_type = client.enums.AdvertisingChannelTypeEnum.PERFORMANCE_MAX
    c.status = client.enums.CampaignStatusEnum.PAUSED
    c.campaign_budget = budget_temp_id
    # Maximize conversions
    client.copy_from(c.maximize_conversions, client.get_type("MaximizeConversions"))
    c.contains_eu_political_advertising = client.enums.EuPoliticalAdvertisingStatusEnum.DOES_NOT_CONTAIN_EU_POLITICAL_ADVERTISING
    mutate_operations.append(campaign_op)

    # CAMPAIGN ASSETS (Solves Brand Guidelines Error)
    mutate_operations.append(create_campaign_asset_op(client, campaign_temp_id, logo_asset, client.enums.AssetFieldTypeEnum.LOGO))
    mutate_operations.append(create_campaign_asset_op(client, campaign_temp_id, biz_name_asset, client.enums.AssetFieldTypeEnum.BUSINESS_NAME))

    # ASSET GROUP
    ag_op = client.get_type("MutateOperation")
    ag = ag_op.asset_group_operation.create
    ag.resource_name = ag_temp_id
    ag.name = f"Universal Asset Group {uid}"
    ag.campaign = campaign_temp_id
    ag.final_urls.append(FINAL_URL)
    ag.status = client.enums.AssetGroupStatusEnum.PAUSED
    mutate_operations.append(ag_op)

    # ASSET GROUP ASSETS
    # Images
    mutate_operations.append(create_asset_group_asset_op(client, ag_temp_id, landscape_asset, client.enums.AssetFieldTypeEnum.MARKETING_IMAGE))
    mutate_operations.append(create_asset_group_asset_op(client, ag_temp_id, square_asset, client.enums.AssetFieldTypeEnum.SQUARE_MARKETING_IMAGE))
    mutate_operations.append(create_asset_group_asset_op(client, ag_temp_id, portrait_asset, client.enums.AssetFieldTypeEnum.PORTRAIT_MARKETING_IMAGE))
    
    # Videos
    for v_asset in video_assets:
        mutate_operations.append(create_asset_group_asset_op(client, ag_temp_id, v_asset, client.enums.AssetFieldTypeEnum.YOUTUBE_VIDEO))
        
    # Text
    for h_asset in headline_assets:
        mutate_operations.append(create_asset_group_asset_op(client, ag_temp_id, h_asset, client.enums.AssetFieldTypeEnum.HEADLINE))
    for lh_asset in long_headline_assets:
        mutate_operations.append(create_asset_group_asset_op(client, ag_temp_id, lh_asset, client.enums.AssetFieldTypeEnum.LONG_HEADLINE))
    for d_asset in desc_assets:
        mutate_operations.append(create_asset_group_asset_op(client, ag_temp_id, d_asset, client.enums.AssetFieldTypeEnum.DESCRIPTION))

    print("5. Firing Atomic Payload...")
    response = google_ads_service.mutate(customer_id=customer_id, mutate_operations=mutate_operations)
    
    print(f"\nSUCCESS! PMax Campaign fully engineered and deployed!")
    print(f"Total Mutate Operations Successful: {len(response.mutate_operation_responses)}")

if __name__ == "__main__":
    try:
        googleads_client = GoogleAdsClient.load_from_storage("google_ads_automation_payload/google-ads.yaml")
        main(googleads_client, CUSTOMER_ID)
    except GoogleAdsException as ex:
        print(f"Google Ads API Error: {ex.error.code().name}")
        for error in ex.failure.errors:
            print(f" -> {error.message}")
            if hasattr(error, 'location'):
                path = ".".join(
                    [element.field_name for element in error.location.field_path_elements]
                )
                print(f"    Location: {path}")
        sys.exit(1)
    except Exception as e:
        print(f"System Error: {e}")
