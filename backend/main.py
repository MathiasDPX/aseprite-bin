from github import Github, Auth
from cachetools import TTLCache, cached
from flask_cors import CORS
from flask import Flask, request
from dotenv import load_dotenv
from os import getenv
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
import semver

load_dotenv()

app = Flask(__name__)
CORS(app)
limiter = Limiter(
    get_remote_address,
    app=app
)

cache_tags = TTLCache(maxsize=8, ttl=60*60)

auth = Auth.Token(getenv("GITHUB_PAT", ""))
g = Github(auth=auth)
repo = g.get_repo(getenv("REPOSITORY", "MathiasDPX/aseprite-bin"))
aseprite_repo = g.get_repo("aseprite/aseprite")

workflow = repo.get_workflow("specific-version.yml")

def get_latests():
    runs = workflow.get_runs()
    latests = {}

    for run in runs:
        if not run.name.startswith("Build aseprite v"):
            continue

        version = run.name.replace("Build aseprite v", "")
        
        status = "unknown"
        if run.status == "completed":
            artifacts = run.get_artifacts()
            if not artifacts:
                status = "expired"

            status = "completed"
        elif run.status == "in_progress":
            status = "in_progress"
        else:
            continue


        latests["v"+version] = {
            "name": run.name,
            "version": version,
            "url": run.html_url,
            "status": status,
            "created": int(run.created_at.timestamp())
        }
        
    return latests

@cached(cache_tags)
def get_tags():
    tags = aseprite_repo.get_tags()
    nametags = []

    for tag in tags:
        name = tag.name
        # Strip leading 'v' just for validation/parsing
        semver_name = name[1:] if name.startswith("v") else name

        if not semver.Version.is_valid(semver_name):
            continue

        nametags.append(name)

    # Sort using semver version, but keep original names
    nametags = sorted(
        nametags,
        key=lambda n: semver.VersionInfo.parse(n[1:] if n.startswith("v") else n),
        reverse=True
    )

    return nametags


@app.route("/tags", methods=["GET"])
def get_tags_route():
    return get_tags()

@app.route("/builds", methods=["GET"])
def latest_builds():
    return get_latests()

@app.route("/build", methods=["POST"])
@limiter.limit("2 per day")
def build_version():
    tag = request.get_data().decode("utf-8")

    if tag not in get_tags():
        return { "success": False, "message": "invalid tag" }

    latests = get_latests()
    if tag in latests:
        if latests[tag]["status"] != "expired":
            return { "success": False, "message": "version already built"}

    success = workflow.create_dispatch("master", inputs={"version": tag})

    return { "success": success }

if __name__ == "__main__":
    app.run()
