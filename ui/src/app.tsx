import { useState, useEffect, useRef } from 'preact/hooks'
import { Clock, MapPin, Play, ChevronUp, ChevronDown } from 'lucide-preact'

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
      if (e.key === 'ArrowDown' || e.key === 's') setSelected(i => (i + 1) % len)
      else if (e.key === 'ArrowUp' || e.key === 'w') setSelected(i => (i - 1 + len) % len)
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
      <div class="player-card">
        <div class="spz-card">
          <div class="card-topbar">
            <span class="spz-eyebrow" style={{ color: 'var(--color-primary)' }}>{player.stateText || 'IDLE'}</span>
            <span class="spz-badge-custom">{licenseClass} Class</span>
          </div>
          <div class="card-body" style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
            <div class="avatar-ring">
              <img src={player.avatar || 'https://i.imgur.com/8NzA8m8.png'} alt="" />
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4, flexWrap: 'wrap' }}>
                <span class="player-name">{player.name || 'Racer'}</span>
                {player.crew && <span class="spz-badge-custom">{player.crew}</span>}
              </div>
              <div class="player-meta">
                <Clock size={11} color="var(--gray-500)" />
                <span class="spz-mono" style={{ fontSize: 11 }}>{formatPlaytime(player.playtime || 0)}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="location-panel">
        <div class="spz-card">
          <div class="panel-title">
            <MapPin size={14} color="var(--color-primary)" />
            <span class="panel-title-text">Select Deployment Zone</span>
          </div>
          <div class="loc-list" ref={listRef}>
            {spawns.map((s, i) => (
              <div
                key={i}
                class={`loc-item${i === selected ? ' active' : ''}`}
                onClick={() => setSelected(i)}
              >
                <span class="loc-num">{String(i + 1).padStart(2, '0')}</span>
                <span class="loc-name">{s.label}</span>
              </div>
            ))}
          </div>
          <div class="panel-hint">
            <ChevronUp size={12} color="var(--gray-500)" />
            <ChevronDown size={12} color="var(--gray-500)" />
            <span class="hint-text">navigate</span>
            <span style={{ color: 'var(--gray-700)', fontSize: 11 }}>·</span>
            <span class="spz-kbd">↵</span>
            <span class="hint-text">confirm</span>
          </div>
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
