import os
import sys
import yaml
import requests
from google_auth_oauthlib.flow import InstalledAppFlow
from google.oauth2.credentials import Credentials
from google.ads.googleads.client import GoogleAdsClient
from google.ads.googleads.errors import GoogleAdsException

# Scopes needed for both YouTube and Google Ads
SCOPES = [
    'https://www.googleapis.com/auth/youtube.readonly',
    'https://www.googleapis.com/auth/adwords'
]

YAML_PATH = "../google_ads_automation_payload/google-ads.yaml"
CUSTOMER_ID = "4602652156"

def load_client_secrets(yaml_path):
    """Extracts client ID and secret from google-ads.yaml to use in OAuth."""
    with open(yaml_path, 'r') as f:
        config = yaml.safe_load(f)
        
    client_id = config.get('client_id')
    client_secret = config.get('client_secret')
    developer_token = config.get('developer_token')
    
    if not client_id or not client_secret:
        print("Error: Could not find client_id or client_secret in google-ads.yaml")
        sys.exit(1)
        
    return {
        "installed": {
            "client_id": client_id,
            "project_id": "openintelligence-auth",
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
            "client_secret": client_secret,
            "redirect_uris": ["http://localhost"]
        }
    }, developer_token

def get_youtube_channel_id(credentials):
    """Fetches the user's YouTube Channel ID via the YouTube Data API."""
    print("Fetching YouTube Channel ID...")
    url = "https://www.googleapis.com/youtube/v3/channels?part=id&mine=true"
    headers = {"Authorization": f"Bearer {credentials.token}"}
    response = requests.get(url, headers=headers)
    
    if response.status_code != 200:
        print(f"Error fetching YouTube channel: {response.text}")
        sys.exit(1)
        
    data = response.json()
    items = data.get("items", [])
    if not items:
        print("Error: No YouTube channel found for this Google account.")
        sys.exit(1)
        
    channel_id = items[0]["id"]
    print(f"Successfully identified YouTube Channel ID: {channel_id}")
    return channel_id

def link_youtube_to_ads(credentials, developer_token, channel_id, customer_id):
    """Uses the Google Ads API to link the YouTube channel."""
    print("Initializing Google Ads API link request...")
    
    # Build a temporary google-ads client config using the new multi-scoped refresh token
    config_dict = {
        "developer_token": developer_token,
        "client_id": credentials.client_id,
        "client_secret": credentials.client_secret,
        "refresh_token": credentials.refresh_token,
        "use_proto_plus": "true"
    }
    
    client = GoogleAdsClient.load_from_dict(config_dict, version="v16")
    
    # Due to API complexities with ProductLinkService vs ProductLinkInvitationService,
    # the exact API call for YouTube linking requires an invitation process if accounts differ,
    # but since this token manages both, we can attempt a direct ProductLink.
    
    try:
        product_link_service = client.get_service("ProductLinkService")
        product_link_operation = client.get_type("ProductLinkOperation")
        
        # Build the YouTube channel link
        product_link = product_link_operation.create
        product_link.youtube_channel.channel_id = channel_id
        
        response = product_link_service.mutate_product_links(
            customer_id=customer_id, operations=[product_link_operation]
        )
        print(f"SUCCESS! Created YouTube Product Link: {response.results[0].resource_name}")
        
    except GoogleAdsException as ex:
        print(f"\n[!] Google Ads API Error linking channel:")
        for error in ex.failure.errors:
            print(f"\tError: {error.error_code.ErrorCode().name}")
            print(f"\tDetails: {error.message}")
        print("\nNote: Google Ads API has extremely strict security constraints around YouTube linking.")
        print("If this API call fails due to permission errors, you must fall back to Option A (linking via the Google Ads UI).")
        sys.exit(1)

def main():
    print("=== OpenIntelligence YouTube Linker ===")
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    
    client_config, developer_token = load_client_secrets(YAML_PATH)
    
    print("\nInitiating OAuth Flow. A browser window will open.")
    print("You MUST sign in with the Google Account that owns the YouTube Channel.")
    
    flow = InstalledAppFlow.from_client_config(client_config, SCOPES)
    # Run local server to catch the redirect
    credentials = flow.run_local_server(port=0)
    
    channel_id = get_youtube_channel_id(credentials)
    
    link_youtube_to_ads(credentials, developer_token, channel_id, CUSTOMER_ID)

if __name__ == "__main__":
    main()
