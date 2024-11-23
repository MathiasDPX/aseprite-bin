from flask import Flask, send_file
import requests
import time
import os

app = Flask(__name__)

cache = {
    "lastFetch": 0,
    "url": ""
}

@app.route("/")
def index():
    current_time = time.time()
    
    if cache["lastFetch"] < current_time - 3600:
        headers = {
            "Accept": "application/vnd.github.v3+json",
            "Authorization": f"Bearer {os.environ.get('ASE_GITHUB_TOKEN')}"
        }
        
        artifacts_response = requests.get(
            "https://api.github.com/repos/sram69/aseprite-bin/actions/artifacts",
            headers=headers
        )
        
        if artifacts_response.status_code != 200:
            return f"Failed to fetch artifacts: {artifacts_response.status_code}", 500
            
        artifacts = artifacts_response.json()
        if not artifacts["artifacts"]:
            return "No artifacts found", 404
            
        artifact = artifacts["artifacts"][0]
        artifact_id = artifact["id"]
        
        download_url = f"https://api.github.com/repos/sram69/aseprite-bin/actions/artifacts/{artifact_id}/zip"
        download_response = requests.get(
            download_url,
            headers=headers,
            allow_redirects=True
        )
        
        if download_response.status_code != 200:
            return f"Failed to download artifact: {download_response.status_code}", 500
            
        with open("artifact.zip", "wb") as f:
            f.write(download_response.content)
            
        cache["lastFetch"] = current_time
        
        return send_file("artifact.zip", as_attachment=True, download_name="aseprite.zip")
    
    if os.path.exists("artifact.zip"):
        return send_file("artifact.zip", as_attachment=True, download_name="aseprite.zip")
        
    return "No artifact available", 404

if __name__ == "__main__":
    if not os.environ.get("ASE_GITHUB_TOKEN"):
        print("Please set ASE_GITHUB_TOKEN environment variable")
        exit(1)
    app.run(host="0.0.0.0")