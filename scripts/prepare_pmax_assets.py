import os
from PIL import Image

def pad_image(img, target_width, target_height, bg_color=(255, 255, 255)):
    """Pads an image to the exact target dimensions without distorting."""
    result = Image.new(img.mode, (target_width, target_height), bg_color)
    x = (target_width - img.width) // 2
    y = (target_height - img.height) // 2
    result.paste(img, (x, y))
    return result

def main():
    base_dir = "/Users/gunnarhostetler/Documents/GitHub"
    output_dir = os.path.join(base_dir, "OpenIntelligence", "google_ads_automation_payload", "pmax_assets")
    
    # 1. Logo (1:1)
    logo_path = os.path.join(base_dir, "Fascinaiting", "assets", "openintelligence_icon.png")
    if os.path.exists(logo_path):
        img = Image.open(logo_path).convert("RGBA")
        img.save(os.path.join(output_dir, "logo_1x1.png"))
        print("Generated logo_1x1.png (1024x1024)")

    # 2. Landscape Banner (1.91:1)
    # Target: 1200x628
    social_path = os.path.join(base_dir, "OpenIntelligence", ".github", "assets", "openintelligence-social-preview.png")
    if os.path.exists(social_path):
        img = Image.open(social_path).convert("RGBA")
        # Scale to fit inside 1200x628
        img.thumbnail((1200, 628), Image.Resampling.LANCZOS)
        landscape = pad_image(img, 1200, 628, (0, 0, 0, 255))
        landscape.save(os.path.join(output_dir, "landscape_191x1.png"))
        print("Generated landscape_191x1.png (1200x628)")
        
        # 3. Square Marketing Image (1:1)
        # Target: 1200x1200
        img = Image.open(social_path).convert("RGBA")
        img.thumbnail((1200, 1200), Image.Resampling.LANCZOS)
        square = pad_image(img, 1200, 1200, (0, 0, 0, 255))
        square.save(os.path.join(output_dir, "square_1x1.png"))
        print("Generated square_1x1.png (1200x1200)")

    # 4. Portrait Banner (4:5)
    # Target: 960x1200
    screen_path = os.path.join(base_dir, "OpenIntelligence", ".github", "assets", "screenshots", "openintelligence-library.png")
    if os.path.exists(screen_path):
        img = Image.open(screen_path).convert("RGBA")
        img.thumbnail((960, 1200), Image.Resampling.LANCZOS)
        portrait = pad_image(img, 960, 1200, (0, 0, 0, 255))
        portrait.save(os.path.join(output_dir, "portrait_4x5.png"))
        print("Generated portrait_4x5.png (960x1200)")

if __name__ == "__main__":
    main()
