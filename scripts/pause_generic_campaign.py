import os
import sys
from google.ads.googleads.client import GoogleAdsClient
from google.ads.googleads.errors import GoogleAdsException

# Load credentials
os.environ["GOOGLE_ADS_DEVELOPER_TOKEN"] = "[REDACTED_SECRET]"
os.environ["GOOGLE_ADS_CLIENT_ID"] = "[REDACTED_SECRET]"
os.environ["GOOGLE_ADS_CLIENT_SECRET"] = "[REDACTED_SECRET]"
os.environ["GOOGLE_ADS_REFRESH_TOKEN"] = "[REDACTED_SECRET]"
os.environ["GOOGLE_ADS_LOGIN_CUSTOMER_ID"] = "[REDACTED_SECRET]"
os.environ["GOOGLE_ADS_USE_PROTO_PLUS"] = "true"

def pause_campaign(customer_id, campaign_name):
    client = GoogleAdsClient.load_from_env(version="v24")
    ga_service = client.get_service("GoogleAdsService")
    
    query = f"""
        SELECT campaign.id, campaign.resource_name, campaign.status, campaign.name
        FROM campaign
        WHERE campaign.name = '{campaign_name}'
    """
    
    try:
        response = ga_service.search(customer_id=customer_id, query=query)
        
        for row in response:
            print(f"Found campaign: {row.campaign.name} (Status: {row.campaign.status})")
            
            camp_service = client.get_service("CampaignService")
            camp_op = client.get_type("CampaignOperation")
            
            client.copy_from(camp_op.update, row.campaign)
            camp_op.update.status = client.enums.CampaignStatusEnum.PAUSED
            
            # Create field mask manually
            camp_op.update_mask.paths.append("status")
            
            camp_response = camp_service.mutate_campaigns(customer_id=customer_id, operations=[camp_op])
            print(f"Successfully PAUSED campaign: {camp_response.results[0].resource_name}")
            
    except GoogleAdsException as ex:
        print(f"API Error: {ex}")

if __name__ == "__main__":
    cust_id = "4509379845"
    pause_campaign(cust_id, "OpenIntelligence_Autonomous_LongTail_Search_V5")
