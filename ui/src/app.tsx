import { useState, useEffect, useRef } from 'preact/hooks'
import { Clock, MapPin, Play, ChevronLeft, ChevronRight } from 'lucide-preact'

interface SpawnPoint {
  label: string
}

interface PlayerData {
  name?: string
  avatar?: string
  licenseClass?: string
  crew?: string
  playtime?: number
  stateText?: string
}

function formatPlaytime(seconds: number): string {
  const hrs = Math.floor(seconds / 3600)
  const mins = Math.floor((seconds % 3600) / 60)
  return `${String(hrs).padStart(2, '0')} HRS ${String(mins).padStart(2, '0')} MINS`
}

export function App() {
  const [visible, setVisible] = useState(false)
  const [player, setPlayer] = useState<PlayerData>({})
  const [spawns, setSpawns] = useState<SpawnPoint[]>([])
  const [selected, setSelected] = useState(0)
  const listRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const handler = (e: MessageEvent) => {
      if (e.data.type === 'show') {
        setPlayer(e.data.playerData || {})
        setSpawns(e.data.spawns || [])
        setSelected(0)
        setVisible(true)
      } else if (e.data.type === 'hide') {
        setVisible(false)
      }
    }
    window.addEventListener('message', handler)
    return () => window.removeEventListener('message', handler)
  }, [])

  useEffect(() => {
    if (!visible) return
    const onKey = (e: KeyboardEvent) => {
      const len = Math.max(1, spawns.length)
      if (e.key === 'ArrowRight' || e.key === 'd') setSelected(i => (i + 1) % len)
      else if (e.key === 'ArrowLeft' || e.key === 'a') setSelected(i => (i - 1 + len) % len)
      else if (e.key === 'Enter') doStart()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [visible, spawns, selected])

  useEffect(() => {
    listRef.current?.querySelector('.active')?.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
  }, [selected])

  const doStart = () => {
    fetch(`https://${GetParentResourceName()}/startSpawn`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ index: selected + 1 }),
    }).catch(() => {})
    setVisible(false)
  }

  if (!visible) return null

  const licenseClass = player.licenseClass || 'D'

  return (
    <>
      <div class="player-card modular-panel">
        <div class="spz-card modular-card title-card" style={{ justifyContent: 'space-between' }}>
          <span class="spz-eyebrow" style={{ color: 'var(--color-primary)' }}>{player.stateText || 'IDLE'}</span>
          <span class="spz-badge-custom">{licenseClass} Class</span>
        </div>
        
        <div class="spz-card modular-card" style={{ padding: '8px 12px', display: 'flex', alignItems: 'center', gap: '10px' }}>
          <div class="avatar-ring" style={{ width: '40px', height: '40px', borderWidth: '1px' }}>
            <img src={player.avatar || 'https://i.imgur.com/8NzA8m8.png'} alt="" />
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginBottom: '2px', flexWrap: 'wrap' }}>
              <span class="player-name" style={{ fontSize: '13px' }}>{player.name || 'Racer'}</span>
              {player.crew && <span class="spz-badge-custom">{player.crew}</span>}
            </div>
            <div class="player-meta">
              <Clock size={10} color="var(--gray-500)" />
              <span class="spz-mono" style={{ fontSize: '10px' }}>{formatPlaytime(player.playtime || 0)}</span>
            </div>
          </div>
        </div>
      </div>

      <div class="location-panel modular-panel">
        <div class="spz-card modular-card title-card">
          <MapPin size={14} color="var(--color-primary)" />
          <span class="panel-title-text">Deployment Zone</span>
        </div>
        
        <div class="spz-card modular-card carousel-card">
          <div class="loc-carousel">
            <div class="loc-nav" onClick={() => setSelected(i => (i - 1 + spawns.length) % spawns.length)}>
              <ChevronLeft size={14} color="var(--color-primary)" />
            </div>
            
            <div class="loc-content">
              <span class="loc-num">{String(selected + 1).padStart(2, '0')}</span>
              <span class="loc-name">{spawns[selected]?.label || 'Unknown'}</span>
            </div>
            
            <div class="loc-nav" onClick={() => setSelected(i => (i + 1) % spawns.length)}>
              <ChevronRight size={14} color="var(--color-primary)" />
            </div>
          </div>
          
          <div class="loc-dots">
            {spawns.map((_, i) => (
              <div class={`loc-dot ${i === selected ? 'active' : ''}`} key={i} />
            ))}
          </div>
        </div>

        <div class="spz-card modular-card hint-card">
          <ChevronLeft size={12} color="var(--gray-500)" />
          <ChevronRight size={12} color="var(--gray-500)" />
          <span class="hint-text">navigate</span>
          <span style={{ color: 'var(--gray-700)', fontSize: 11 }}>·</span>
          <span class="spz-kbd">↵</span>
          <span class="hint-text">confirm</span>
        </div>
      </div>

      <div class="start-wrap">
        <div class="start-btn" onClick={doStart}>
          <div class="start-btn-text">Spawn</div>
          <div class="start-btn-icon"><Play size={16} /></div>
        </div>
      </div>
    </>
  )
}
