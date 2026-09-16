import sys
import json

def process_payload(raw_input):
    try:
        data = json.loads(raw_input)
        items = data.get("items", [])
        processed_items = []
        
        for item in items:
            if "title" in item and "type" in item:
                processed_items.append({
                    "id": item.get("id"),
                    "title": item.get("title"),
                    "type": item.get("type"),
                    "stream_url": item.get("stream_url", ""),
                    "info_hash": item.get("info_hash", ""),
                    "art": item.get("art", "")
                })
                
        return json.dumps({
            "status": "success",
            "items": processed_items
        })
    except Exception as e:
        return json.dumps({
            "status": "error",
            "message": str(e)
        })

if __name__ == "__main__":
    input_data = sys.stdin.read() if len(sys.argv) < 2 else sys.argv[1]
    print(process_payload(input_data))
