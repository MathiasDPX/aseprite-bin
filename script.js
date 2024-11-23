const hadWarning = localStorage.getItem("hadFirstTimePopup");

if (hadWarning != "true") {
    alert("I only build aseprite for you. For safety, build it yourself. If you can, support aseprite developers by buying a license on Steam");
    localStorage.setItem("hadFirstTimePopup", "true");
}

function onDownload() {
    document.getElementsByClassName("download-button")[0].innerHTML = "Download in progress..."
}