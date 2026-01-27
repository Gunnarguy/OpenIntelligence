# HomeSync Pro User Guide

## Whole-Home Automation Hub | Model HSP-3000

**Version:** 2.1
**Last Updated:** October 2025
**Support:** support@homesyncdevices.com

---

## Quick Start

### What's in the Box

- HomeSync Pro Hub (HSP-3000)
- Power adapter (12V / 2.5A)
- Ethernet cable (6 ft / 1.8m)
- Quick start guide
- Wall mount kit

### Initial Setup

1. **Connect Power:** Plug the power adapter into the hub and a wall outlet
2. **Wait for Boot:** The status LED will cycle through colors (approximately 90 seconds)
3. **Connect Network:** Use the included Ethernet cable OR wait for Wi-Fi setup
4. **Download App:** Get "HomeSync" from App Store or Google Play
5. **Create Account:** Open the app and follow the registration prompts
6. **Add Hub:** Tap "+" then "Add HomeSync Hub" and follow pairing instructions

**First-Time Setup Duration:** Approximately 5-10 minutes

---

## Product Comparison

### HomeSync Model Lineup

| Feature               | HomeSync Lite (HSL-1000) | HomeSync Pro (HSP-3000)               | HomeSync Ultra (HSU-5000) |
| --------------------- | ------------------------ | ------------------------------------- | ------------------------- |
| **Price**             | $149                     | $299                                  | $499                      |
| **Supported Devices** | Up to 50                 | Up to 200                             | Up to 500                 |
| **Protocols**         | Wi-Fi, Zigbee            | Wi-Fi, Zigbee, Z-Wave, Thread, Matter | All + proprietary RF      |
| **Voice Assistants**  | Alexa, Google            | Alexa, Google, Siri, Samsung          | All + local voice         |
| **Processor**         | Quad-core 1.2 GHz        | Quad-core 1.8 GHz                     | Octa-core 2.4 GHz         |
| **RAM**               | 1 GB                     | 2 GB                                  | 4 GB                      |
| **Storage**           | 8 GB                     | 16 GB                                 | 64 GB                     |
| **Local Processing**  | Basic                    | Advanced                              | Full AI                   |
| **Backup Battery**    | No                       | 4 hours                               | 12 hours                  |
| **Warranty**          | 1 year                   | 2 years                               | 3 years                   |

### Why Choose HomeSync Pro?

The HomeSync Pro (HSP-3000) is our most popular model because it offers:

- **Matter Support:** Future-proof compatibility with the new smart home standard
- **Thread Border Router:** Built-in Thread radio for low-power device mesh
- **Z-Wave Plus:** 868/908 MHz support for legacy devices
- **4-Hour Backup:** Continues operating during power outages
- **Local Automations:** Routines execute without cloud connectivity

---

## Connecting Devices

### Supported Protocols

The HomeSync Pro supports the following communication protocols:

| Protocol     | Frequency | Range  | Max Devices | Best For           |
| ------------ | --------- | ------ | ----------- | ------------------ |
| Wi-Fi 6      | 2.4/5 GHz | 150 ft | Unlimited\* | Cameras, displays  |
| Zigbee 3.0   | 2.4 GHz   | 100 ft | 150         | Sensors, lights    |
| Z-Wave Plus  | 908 MHz   | 300 ft | 50          | Locks, thermostats |
| Thread       | 2.4 GHz   | 100 ft | 250         | Modern low-power   |
| Bluetooth LE | 2.4 GHz   | 30 ft  | 20          | Beacons, presence  |
| Matter       | Various   | Varies | 200         | Cross-platform     |

\*Wi-Fi devices are limited by your router, not HomeSync Pro

### Adding a New Device

1. Open the HomeSync app
2. Tap the "+" button in the top right
3. Select device category (Lights, Sensors, Locks, etc.)
4. Choose your device brand and model
5. Put the device in pairing mode (see device manual)
6. HomeSync will discover and add the device automatically
7. Assign a name and room for the device

**Pairing Timeout:** Devices must enter pairing mode within 3 minutes of starting the add process.

### Device Naming Best Practices

- Use room + device type: "Kitchen Ceiling Light"
- Avoid special characters
- Keep names under 32 characters
- Use consistent naming across similar devices

---

## Automations & Routines

### Creating an Automation

Automations trigger actions based on conditions:

**Trigger Types:**

- Time-based (sunrise, sunset, specific time)
- Device state (motion detected, door opened)
- Location (arrive home, leave home)
- Weather (temperature, humidity, rain)
- Manual (button press, voice command)

**Condition Types:**

- Time window (only between 6 PM and 11 PM)
- Device state (only if lights are off)
- Mode (only in Home mode, not Away mode)
- Presence (only if someone is home)

**Action Types:**

- Control devices (turn on, off, set level)
- Send notifications (push, SMS, email)
- Activate scenes
- Trigger other automations
- Wait (delay before next action)

### Example Automations

**"Goodnight" Routine:**

- Trigger: Voice command "Goodnight" or button press
- Actions:
  1. Turn off all lights
  2. Lock all doors
  3. Set thermostat to 68°F
  4. Arm security system (Home mode)
  5. Turn on bedroom fan at 30%

**"Motion Kitchen Night":**

- Trigger: Motion sensor detects movement
- Conditions: Time is between 10 PM and 6 AM
- Actions:
  1. Turn on under-cabinet lights at 20%
  2. After 5 minutes of no motion, turn off

### Automation Limits

| HomeSync Model   | Max Automations | Max Actions per Automation | Max Conditions |
| ---------------- | --------------- | -------------------------- | -------------- |
| Lite (HSL-1000)  | 25              | 10                         | 3              |
| Pro (HSP-3000)   | 100             | 25                         | 10             |
| Ultra (HSU-5000) | Unlimited       | 50                         | Unlimited      |

---

## Security Features

### Alarm Modes

The HomeSync Pro supports four security modes:

| Mode         | Sensors Active                    | Entry Delay | Alert Type         |
| ------------ | --------------------------------- | ----------- | ------------------ |
| **Disarmed** | None                              | N/A         | None               |
| **Home**     | Doors, windows, glass break       | 30 seconds  | Push notification  |
| **Away**     | All sensors including motion      | 45 seconds  | Push + SMS + Siren |
| **Night**    | Doors, windows, downstairs motion | 15 seconds  | Push + Siren       |

### Setting Up Alerts

1. Go to Settings > Security > Alerts
2. Choose which events trigger notifications:
   - Door/window opened
   - Motion detected
   - Glass break detected
   - Water leak detected
   - Smoke/CO detected
   - Temperature out of range
3. Select notification methods:
   - Push notification (free, unlimited)
   - SMS (requires HomeSync Pro subscription, 100/month)
   - Phone call (requires HomeSync Pro subscription, 20/month)
   - Email (free, unlimited)

### Professional Monitoring (Optional)

HomeSync Pro is compatible with professional monitoring services:

| Service                | Monthly Cost | Features                                         |
| ---------------------- | ------------ | ------------------------------------------------ |
| HomeSync Guard Basic   | $9.99/month  | 24/7 monitoring, police dispatch                 |
| HomeSync Guard Plus    | $19.99/month | Basic + fire/medical, cellular backup            |
| HomeSync Guard Premium | $29.99/month | Plus + video verification, insurance certificate |

**Contract:** No long-term contract required. Cancel anytime.

---

## Troubleshooting

### Status LED Guide

| LED Color       | Pattern      | Meaning                                |
| --------------- | ------------ | -------------------------------------- |
| Blue solid      | Steady       | Normal operation                       |
| Blue blinking   | Slow (1/sec) | Updating firmware                      |
| Green blinking  | Fast (3/sec) | Pairing mode active                    |
| Yellow solid    | Steady       | Internet disconnected (local only)     |
| Yellow blinking | Slow         | Cloud connection issue                 |
| Red solid       | Steady       | Critical error - restart required      |
| Red blinking    | Fast         | Hardware failure - contact support     |
| White cycling   | Rainbow      | First boot / factory reset in progress |

### Common Issues

**Problem:** Hub offline in app but devices still work
**Solution:** This indicates a cloud connectivity issue. Local automations continue to work. Check your internet connection and router settings. Ensure ports 443 and 8883 are not blocked.

**Problem:** Device shows "Unavailable"
**Cause:** The device has lost connection to the hub
**Solutions:**

1. Check device power and batteries
2. Move device closer to hub or add a Zigbee/Z-Wave repeater
3. Remove and re-add the device
4. Check for wireless interference (2.4 GHz congestion)

**Problem:** Automations not running at correct time
**Solution:** Verify timezone in Settings > System > Time Zone. Check that sunrise/sunset location is set correctly.

**Problem:** Voice commands not working
**Solutions:**

1. Ensure voice assistant integration is connected (Settings > Integrations)
2. Use exact device names in commands
3. Check that skill/action is enabled in voice assistant app
4. Try "Hey Google/Alexa, sync my devices"

### Factory Reset

**⚠️ Warning:** This erases all settings, devices, and automations.

To factory reset the HomeSync Pro:

1. Locate the reset button (small hole on bottom of unit)
2. Press and hold for 15 seconds using a paperclip
3. LED will turn red, then begin rainbow cycling
4. Release button and wait 3 minutes for reset to complete
5. Hub will enter first-time setup mode

---

## Specifications

### Hardware

| Component      | Specification                          |
| -------------- | -------------------------------------- |
| Processor      | ARM Cortex-A53 Quad-core @ 1.8 GHz     |
| RAM            | 2 GB DDR4                              |
| Storage        | 16 GB eMMC                             |
| Wi-Fi          | 802.11ax (Wi-Fi 6) dual-band           |
| Ethernet       | Gigabit (10/100/1000)                  |
| Zigbee         | Silicon Labs EFR32MG21                 |
| Z-Wave         | Silicon Labs ZGM130S (700 series)      |
| Thread         | OpenThread Border Router               |
| Bluetooth      | BLE 5.2                                |
| Backup Battery | 3.7V 6000mAh Li-ion (4 hours typical)  |
| Power Input    | 12V DC / 2.5A (30W)                    |
| Dimensions     | 5.5" × 5.5" × 1.5" (140 × 140 × 38 mm) |
| Weight         | 14.2 oz (403 g)                        |
| Operating Temp | 32°F to 104°F (0°C to 40°C)            |

### Software

| Feature           | Details                             |
| ----------------- | ----------------------------------- |
| Operating System  | HomeSync OS 4.2 (Linux-based)       |
| App Compatibility | iOS 15+, Android 10+                |
| API               | REST API, WebSocket, MQTT           |
| Local API         | Available with Pro subscription     |
| Firmware Updates  | Automatic (configurable)            |
| Backup            | Daily cloud backup of configuration |

---

## Warranty & Support

### Warranty Terms

The HomeSync Pro (HSP-3000) is covered by a **2-year limited warranty** from date of purchase.

**What's Covered:**

- Manufacturing defects
- Hardware failures under normal use
- Battery degradation below 50% capacity

**What's NOT Covered:**

- Physical damage (drops, liquid, impact)
- Damage from power surges (use surge protector)
- Unauthorized modifications or repairs
- Normal wear and cosmetic damage
- Accessories (power adapter warrantied separately for 1 year)

### Getting Support

**Online Resources:**

- Knowledge Base: help.homesyncdevices.com
- Community Forum: community.homesyncdevices.com
- Video Tutorials: youtube.com/homesyncdevices

**Contact Support:**

- Email: support@homesyncdevices.com
- Phone: 1-888-466-3796 (1-888-HOMESYNC)
- Hours: Monday-Friday 8 AM - 8 PM ET, Saturday 9 AM - 5 PM ET
- Chat: Available in the HomeSync app

**Response Times:**
| Channel | Typical Response |
|---------|-----------------|
| Email | Within 24 hours |
| Phone | Less than 5 minutes |
| Chat | Less than 2 minutes |

---

## Subscription Plans

### HomeSync Pro Subscription

Optional subscription unlocks additional features:

| Feature                 | Free    | Pro ($4.99/mo) | Pro+ ($9.99/mo) |
| ----------------------- | ------- | -------------- | --------------- |
| Device limit            | 200     | 200            | 200             |
| Automations             | 100     | 100            | 100             |
| Cloud backup            | 7 days  | 30 days        | 1 year          |
| Activity history        | 3 days  | 30 days        | 1 year          |
| SMS alerts              | 0/month | 100/month      | Unlimited       |
| Phone call alerts       | 0/month | 20/month       | 100/month       |
| Local API access        | No      | Yes            | Yes             |
| Priority support        | No      | No             | Yes             |
| Remote access (VPN)     | No      | Yes            | Yes             |
| Advanced energy reports | No      | No             | Yes             |

**Annual discount:** Save 20% with annual billing.

---

_HomeSync, HomeSync Pro, and HomeSync Devices are trademarks of HomeSync Technologies, LLC._
_Made in USA. FCC ID: 2AYHZ-HSP3000_
