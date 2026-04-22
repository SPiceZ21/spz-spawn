let spawns = [];
let currentIndex = 0;

window.addEventListener('message', function(event) {
    const data = event.data;

    if (data.type === 'show') {
        document.getElementById('app').style.display = 'flex';
        document.getElementById('player-name').innerText = data.playerData.name;
        document.getElementById('playtime-val').innerText = formatPlaytime(data.playerData.playtime);
        
        spawns = data.spawns;
        currentIndex = 0;
        updateSpawnDisplay();
        createDots();
    } else if (data.type === 'hide') {
        document.getElementById('app').style.display = 'none';
    }
});

function formatPlaytime(seconds) {
    const hrs = Math.floor(seconds / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    return `${hrs.toString().padStart(2, '0')} HRS ${mins.toString().padStart(2, '0')} MINS`;
}

function updateSpawnDisplay() {
    if (spawns.length === 0) return;
    const label = document.getElementById('spawn-label');
    label.style.opacity = '0';
    
    setTimeout(() => {
        label.innerText = spawns[currentIndex].label;
        label.style.opacity = '1';
        updateDots();
    }, 200);
}

function createDots() {
    const container = document.getElementById('selector-dots');
    container.innerHTML = '';
    spawns.forEach((_, index) => {
        const dot = document.createElement('div');
        dot.className = 'dot' + (index === currentIndex ? ' active' : '');
        container.appendChild(dot);
    });
}

function updateDots() {
    const dots = document.querySelectorAll('.dot');
    dots.forEach((dot, index) => {
        if (index === currentIndex) {
            dot.classList.add('active');
        } else {
            dot.classList.remove('active');
        }
    });
}

function nextSpawn() {
    currentIndex = (currentIndex + 1) % spawns.length;
    updateSpawnDisplay();
}

function prevSpawn() {
    currentIndex = (currentIndex - 1 + spawns.length) % spawns.length;
    updateSpawnDisplay();
}

function startSpawn() {
    fetch(`https://${GetParentResourceName()}/startSpawn`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json; charset=UTF-8',
        },
        body: JSON.stringify({
            index: currentIndex + 1 // 1-indexed for Lua if needed, or just send index
        })
    }).then(resp => resp.json());
}

// Keybind support
window.addEventListener('keydown', function(event) {
    if (event.key === 'Enter') {
        startSpawn();
    } else if (event.key === 'ArrowRight' || event.key === 'd') {
        nextSpawn();
    } else if (event.key === 'ArrowLeft' || event.key === 'a') {
        prevSpawn();
    }
});
