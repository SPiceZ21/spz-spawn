let spawns = [];
let currentIndex = 0;

window.addEventListener('message', function(event) {
    const data = event.data;

    if (data.type === 'show') {
        document.getElementById('app').style.display = 'flex';
        
        // Populate Nametag
        document.getElementById('player-name').innerText = data.playerData.name || "RACER";
        document.getElementById('playtime-val').innerText = formatPlaytime(data.playerData.playtime || 0);
        document.getElementById('player-avatar').src = data.playerData.avatar || "https://i.imgur.com/8NzA8m8.png";
        
        const crewSpan = document.getElementById('player-crew');
        if (data.playerData.crew && data.playerData.crew.length > 0) {
            crewSpan.innerText = data.playerData.crew;
            crewSpan.style.display = 'inline-block';
        } else {
            crewSpan.style.display = 'none';
        }
        
        document.getElementById('player-license').innerText = `${data.playerData.licenseClass || 'D'} CLASS`;
        document.getElementById('nametag-bg-num').innerText = data.playerData.licenseClass || 'D';
        document.getElementById('player-state').innerText = data.playerData.stateText || 'IDLE';

        spawns = data.spawns || [];
        currentIndex = 0;
        renderLocations();
    } else if (data.type === 'hide') {
        document.getElementById('app').style.display = 'none';
    }
});

function formatPlaytime(seconds) {
    const hrs = Math.floor(seconds / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    return `${hrs.toString().padStart(2, '0')} HRS ${mins.toString().padStart(2, '0')} MINS`;
}

function renderLocations() {
    const container = document.getElementById('location-list');
    container.innerHTML = '';
    
    spawns.forEach((spawn, index) => {
        const item = document.createElement('div');
        item.className = 'location-item' + (index === currentIndex ? ' active' : '');
        item.innerHTML = `
            <div class="bg-num">${(index + 1).toString().padStart(2, '0')}</div>
            <div class="location-num">${(index + 1).toString().padStart(2, '0')}</div>
            <div class="location-name">${spawn.label}</div>
        `;
        item.onclick = () => selectLocation(index);
        container.appendChild(item);
    });
    
    scrollToActive();
}

function selectLocation(index) {
    currentIndex = index;
    const items = document.querySelectorAll('.location-item');
    items.forEach((item, i) => {
        if (i === currentIndex) item.classList.add('active');
        else item.classList.remove('active');
    });
    scrollToActive();
}

function scrollToActive() {
    const activeItem = document.querySelector('.location-item.active');
    if (activeItem) {
        activeItem.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }
}

function nextSpawn() {
    if (spawns.length === 0) return;
    selectLocation((currentIndex + 1) % spawns.length);
}

function prevSpawn() {
    if (spawns.length === 0) return;
    selectLocation((currentIndex - 1 + spawns.length) % spawns.length);
}

function startSpawn() {
    fetch(`https://${GetParentResourceName()}/startSpawn`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({ index: currentIndex + 1 })
    }).then(resp => resp.json()).catch(err => console.error(err));
}

window.addEventListener('keydown', function(event) {
    // Only capture keys if the app is visible
    if (document.getElementById('app').style.display === 'none') return;
    
    if (event.key === 'Enter') {
        startSpawn();
    } else if (event.key === 'ArrowDown' || event.key === 's') {
        nextSpawn();
    } else if (event.key === 'ArrowUp' || event.key === 'w') {
        prevSpawn();
    }
});
