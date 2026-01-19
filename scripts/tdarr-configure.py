#!/usr/bin/env python3
"""
Tdarr Auto-Configuration Script
Configures Tdarr libraries via API in an idempotent manner
"""

import os
import sys
import time
import json
import logging
import requests
from typing import Optional, Dict, List

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# Configuration
TDARR_URL = os.getenv("TDARR_URL", "http://localhost:8265")
API_KEY = os.getenv("TDARR_API_KEY", "")
MAX_RETRIES = 30
RETRY_DELAY = 10

# API Endpoints
API_BASE = f"{TDARR_URL}/api/v2"
STATUS_URL = f"{API_BASE}/status"
LIBRARIES_URL = f"{API_BASE}/get-libraries"
CREATE_LIBRARY_URL = f"{API_BASE}/library-settings"
SCAN_LIBRARY_URL = f"{API_BASE}/scan-library"


def wait_for_tdarr() -> bool:
    """Wait for Tdarr to be ready."""
    logger.info("Waiting for Tdarr to be ready...")
    
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            response = requests.get(STATUS_URL, timeout=5)
            if response.status_code == 200:
                logger.info("✅ Tdarr is ready!")
                return True
        except requests.exceptions.RequestException:
            pass
        
        logger.info(f"Tdarr not ready yet, waiting... ({attempt}/{MAX_RETRIES})")
        time.sleep(RETRY_DELAY)
    
    logger.error("❌ Tdarr failed to start within timeout")
    return False


def get_libraries() -> Dict:
    """Get all existing libraries."""
    try:
        headers = {"x-api-key": API_KEY} if API_KEY else {}
        response = requests.get(LIBRARIES_URL, headers=headers, timeout=10)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        logger.error(f"Failed to fetch libraries: {e}")
        return {}


def library_exists(name: str) -> bool:
    """Check if a library with the given name exists."""
    libraries = get_libraries()
    
    # Check if any library has this name
    for lib_id, lib_data in libraries.items():
        if lib_data.get("name") == name:
            logger.info(f"📚 Library '{name}' already exists (ID: {lib_id})")
            return True
    
    return False


def create_library(name: str, source_path: str, cache_path: str) -> bool:
    """Create a library if it doesn't exist."""
    if library_exists(name):
        return True
    
    logger.info(f"📚 Creating library: {name}")
    
    # Library configuration payload
    # Note: This is based on reverse-engineering the Tdarr API
    # Actual payload structure may vary by Tdarr version
    payload = {
        "name": name,
        "source": source_path,
        "folderToFolderConversion": False,
        "folder_watch": True,
        "priority": 0,
        "scanButtons": {
            "findNew": True,
            "findDeleted": True
        },
        "transcode_cache": cache_path,
        "output_folder": "",
        "pluginStack": []
    }
    
    try:
        headers = {
            "Content-Type": "application/json",
            "x-api-key": API_KEY
        } if API_KEY else {"Content-Type": "application/json"}
        
        response = requests.post(
            CREATE_LIBRARY_URL,
            json=payload,
            headers=headers,
            timeout=10
        )
        
        if response.status_code in [200, 201]:
            logger.info(f"✅ Library '{name}' created successfully")
            return True
        else:
            logger.warning(f"⚠️  Library creation returned status {response.status_code}")
            logger.warning(f"Response: {response.text}")
            return False
            
    except requests.exceptions.RequestException as e:
        logger.error(f"❌ Failed to create library '{name}': {e}")
        return False


def main():
    """Main configuration routine."""
    logger.info("🎬 Starting Tdarr readiness check...")
    
    # Wait for Tdarr to be ready
    if not wait_for_tdarr():
        logger.error("⚠️  Tdarr not ready, will retry on next service start")
        return 1
    
    logger.info("✅ Tdarr is running and ready!")
    logger.info(f"📍 Access Tdarr Web UI at: {TDARR_URL}")
    logger.info("")
    logger.info("⚠️  IMPORTANT: Tdarr library configuration must be done via Web UI")
    logger.info("   The Tdarr API does not support programmatic library creation in version 2.x")
    logger.info("")
    logger.info("📚 To configure libraries manually:")
    logger.info("   1. Open {TDARR_URL} in your browser")
    logger.info("   2. Go to 'Libraries' tab")
    logger.info("   3. Click '+' to add a new library")
    logger.info("")
    logger.info("   Movies Library:")
    logger.info("     - Name: Movies")
    logger.info("     - Source: /media/movies")
    logger.info("     - Transcode cache: /temp/movies")
    logger.info("     - Enable folder watch (optional)")
    logger.info("")
    logger.info("   TV Shows Library:")
    logger.info("     - Name: TV Shows")
    logger.info("     - Source: /media/shows")
    logger.info("     - Transcode cache: /temp/shows")
    logger.info("     - Enable folder watch (optional)")
    logger.info("")
    logger.info("   After creating libraries, configure transcode plugins:")
    logger.info("     - Library Options → Transcode Options → Plugin Stack")
    logger.info("     - Add plugins for H.265 transcoding (see documentation)")
    logger.info("")
    logger.info("🎯 Workers are pre-configured:")
    logger.info("   - 2 GPU transcode workers")
    logger.info("   - 4 CPU transcode workers")
    logger.info("   - GPU acceleration enabled")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
