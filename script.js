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