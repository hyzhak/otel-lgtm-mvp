import os
import random
import time
import httpx

BASE = os.getenv("TARGET_BASE_URL", "http://localhost:8000")

while True:
    try:
        # 80% normal, 19% work (100–500ms), 1% errors
        p = random.random()
        if p < 0.01:
            httpx.get(f"{BASE}/error", timeout=5)
            print('Error request')
        elif p < 0.20:
            ms = random.randint(100, 500)
            httpx.get(f"{BASE}/work", params={"ms": ms}, timeout=5)
            print(f'Work request: {ms}ms')
        else:
            httpx.get(f"{BASE}/", timeout=5)
            print('Normal request')
    except Exception as e:
        print(f"Error occurred: {e}")
    time.sleep(0.4)
