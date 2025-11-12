const hadWarning = localStorage.getItem("hadFirstTimePopup");

if (hadWarning != "true") {
    alert("I only build aseprite for you. For safety, build it yourself. If you can, support aseprite developers by buying a license on Steam");
    localStorage.setItem("hadFirstTimePopup", "true");
}

function macos_alert() {
    alert("If Aseprite doesn't open, run 'xattr -cr Aseprite.app' in terminal")
}

function getRelativeTimeString(date) {
    const now = new Date();
    const diffMs = now - date;
    const diffMinutes = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMs / 3600000);
    
    if (diffMinutes < 1) {
        return 'just now';
    } else if (diffMinutes < 60) {
        return `${diffMinutes} minute${diffMinutes > 1 ? 's' : ''} ago`;
    } else if (diffHours < 24) {
        return `${diffHours} hour${diffHours > 1 ? 's' : ''} ago`;
    }
    
    return null; // more than 24 hours
}

async function updateBuildTimes() {
    try {
        const response = await fetch('https://api.github.com/repos/MathiasDPX/aseprite-bin/actions/runs');
        const data = await response.json();
        
        const workflowMap = {
            'macOS build': 'macos-build-time',
            'Linux build': 'linux-build-time',
            'Windows build': 'windows-build-time'
        };
        
        const latestRuns = {};
        
        data.workflow_runs.forEach(run => {
            const displayName = run.display_title || run.name;
            
            if (workflowMap[displayName] && run.status === 'completed') {
                if (!latestRuns[displayName] || new Date(run.updated_at) > new Date(latestRuns[displayName].updated_at)) {
                    latestRuns[displayName] = run;
                }
            }
        });
        
        Object.keys(latestRuns).forEach(displayName => {
            const elementId = workflowMap[displayName];
            const element = document.getElementById(elementId);
            
            if (element) {
                const buildDate = new Date(latestRuns[displayName].updated_at);
                const relativeTime = getRelativeTimeString(buildDate);
                
                fullDate = buildDate.toLocaleString('en-US', {
                    year: 'numeric',
                    month: 'short',
                    day: 'numeric',
                    hour: '2-digit',
                    minute: '2-digit'
                });

                let formattedDate;
                if (relativeTime) {
                    // use relative time
                    formattedDate = relativeTime;
                } else {
                    formattedDate = fullDate;
                }

                element.textContent = `Last build: ${formattedDate}`;
                element.title = fullDate;
            }
        });
    } catch (error) {
        console.error('Error fetching build times:', error);
    }
}

updateBuildTimes();

async function populateTags() {
    const select = document.getElementById('version-select');
    if (!select) return;

    try {
        const response = await fetch('https://aseprite.mathias.hackclub.app/tags');
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const tags = await response.json();

        tags.forEach(tag => {
            const option = document.createElement('option');
            option.textContent = tag;
            select.appendChild(option);

        });
    } catch (error) {
        console.error('Error fetching builds from API:', error);
    }
}

async function populateVersionsList() {
    const ul = document.getElementById('versions-list');
    if (!ul) return;

    try {
        const response = await fetch('https://aseprite.mathias.hackclub.app/builds');
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const json = await response.json();

        let builds = [];
        if (Array.isArray(json)) {
            builds = json;
        } else if (json && typeof json === 'object') {
            builds = Object.entries(json).map(([key, data]) => {
                return Object.assign({}, data, { _key: key });
            });
        }

        if (!builds || builds.length === 0) {
            console.info('No builds returned from local API; keeping placeholder list.');
            return;
        }

        builds = builds.map(item => {
            const out = Object.assign({}, item);
            const created = out.created || out.time || out.timestamp || out.created_at || null;
            if (created != null) {
                const num = Number(created);
                if (!Number.isNaN(num)) {
                    out._created = (num < 1e12) ? num * 1000 : num;
                }
            }
            return out;
        }).sort((a, b) => (b._created || 0) - (a._created || 0));

        const statusColors = {
            in_progress: '#DD612B',
            completed: '#6EC07A',
            expired: '#8B8B9C'
        };

        builds.forEach(item => {
            const key = item._key || ('v' + (item.version || 'unknown'));
            const versionText = key.startsWith('v') ? key : ('v' + (item.version || key));
            const url = item.url || item.html_url || item.release_url || item.releaseUrl || item['url'] || '#';

            const li = document.createElement('li');

            const a = document.createElement('a');
            a.className = 'version-link';
            a.href = url || '#';
            a.target = '_blank';
            a.textContent = versionText;

            const metaDiv = document.createElement('div');
            metaDiv.className = 'version-meta';

            const spanDate = document.createElement('span');
            spanDate.className = 'version-date';
            if (item._created) {
                const d = new Date(item._created);
                const rel = getRelativeTimeString(d);
                spanDate.textContent = rel || d.toLocaleString();
                spanDate.title = d.toLocaleString();
            } else {
                spanDate.textContent = 'unknown';
            }

            const spanStatus = document.createElement('span');
            spanStatus.className = 'status';
            const statusRaw = (item.status || item.state || '').toString().toLowerCase();
            const status = statusRaw;
            if (item.expired) {
                status = "expired";
            }

            spanStatus.textContent = status;
            spanStatus.style.color = statusColors[status] || '#000000';

            metaDiv.appendChild(spanDate);
            metaDiv.appendChild(spanStatus);

            li.appendChild(a);
            li.appendChild(metaDiv);

            ul.appendChild(li);
        });

    } catch (error) {
        console.error('Error fetching builds from API:', error);
    }
}

populateTags();
populateVersionsList();

// Build button handler
const buildButton = document.getElementById('build-button');
if (buildButton) {
    buildButton.addEventListener('click', async () => {
        const select = document.getElementById('version-select');
        const tag = select?.value;
        
        if (!tag) {
            alert('Please select a version first');
            return;
        }
        
        try {
            const response = await fetch('https://aseprite.mathias.hackclub.app/build', {
                method: 'POST',
                body: tag
            });
            
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }
            
            const result = await response.json();
            console.log('Build response:', result);
        } catch (error) {
            console.error('Error starting build:', error);
            alert('Failed to start build. Check console for details.');
        }
    });
}
