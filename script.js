const hadWarning = localStorage.getItem("hadFirstTimePopup");

if (hadWarning != "true") {
    alert("I only build aseprite for you. For safety, build it yourself. If you can, support aseprite developers by buying a license on Steam");
    localStorage.setItem("hadFirstTimePopup", "true");
}

function macos_alert() {
    alert("If Aseprite doesn't open, run 'xattr -cr Aseprite.app' in terminal")
}