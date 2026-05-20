import { useState, useEffect, useRef } from 'preact/hooks'
import { Clock, MapPin, Play, ChevronLeft, ChevronRight, User, Sparkles, Check, AlertCircle, Fingerprint } from 'lucide-preact'

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
  const [view, setView] = useState<'none' | 'spawn' | 'creation'>('none')
  const [player, setPlayer] = useState<PlayerData>({})
  const [spawns, setSpawns] = useState<SpawnPoint[]>([])
  const [selected, setSelected] = useState(0)
  const [creationError, setCreationError] = useState<string | null>(null)
  const listRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const handler = (e: MessageEvent) => {
      if (e.data.type === 'show') {
        setPlayer(e.data.playerData || {})
        setSpawns(e.data.spawns || [])
        setSelected(0)
        setView('spawn')
      } else if (e.data.type === 'showCharacterCreation') {
        setCreationError(null)
        setView('creation')
      } else if (e.data.type === 'characterCreationError') {
        setCreationError(e.data.message || 'An error occurred.')
      } else if (e.data.type === 'hide') {
        setView('none')
      }
    }
    window.addEventListener('message', handler)
    return () => window.removeEventListener('message', handler)
  }, [])

  useEffect(() => {
    if (view !== 'spawn') return
    const onKey = (e: KeyboardEvent) => {
      const len = Math.max(1, spawns.length)
      if (e.key === 'ArrowRight' || e.key === 'd') setSelected(i => (i + 1) % len)
      else if (e.key === 'ArrowLeft' || e.key === 'a') setSelected(i => (i - 1 + len) % len)
      else if (e.key === 'Enter') doStart()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [view, spawns, selected])

  useEffect(() => {
    listRef.current?.querySelector('.active')?.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
  }, [selected])

  const doStart = () => {
    fetch(`https://${GetParentResourceName()}/startSpawn`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ index: selected + 1 }),
    }).catch(() => {})
    setView('none')
  }

  if (view === 'none') return null

  if (view === 'creation') {
    return <CharacterCreation serverError={creationError} onClearError={() => setCreationError(null)} />
  }

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

function CharacterCreation({ serverError, onClearError }: { serverError: string | null, onClearError: () => void }) {
  const [name, setName] = useState('');
  const [gender, setGender] = useState(0);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (serverError) setSubmitting(false);
  }, [serverError]);

  const isValidName = /^[a-zA-Z0-9_]{3,16}$/.test(name);

  const submitCreation = () => {
    if (!isValidName || submitting) return;
    setSubmitting(true);
    onClearError();
    fetch(`https://${GetParentResourceName()}/submitCharacterCreation`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, gender }),
    }).catch(() => { setSubmitting(false) })
  }

  return (
    <div class="spz-overlay custom-overlay-blur">
      <div class="identity-panel identity-panel-anim">
        <div class="spz-card modular-card title-card" style={{ justifyContent: 'center', gap: '8px' }}>
          <Fingerprint size={16} color="var(--color-primary)" />
          <span class="panel-title-text" style={{ color: 'var(--color-primary)', fontSize: '12px' }}>Initialize Racer Profile</span>
        </div>

        {serverError && (
          <div class="spz-card modular-card" style={{ padding: '10px 14px', background: 'rgba(239,68,68,0.08)', border: '1px solid rgba(239,68,68,0.3)', display: 'flex', alignItems: 'center', gap: '8px' }}>
            <AlertCircle size={14} color="#ef4444" />
            <span style={{ fontSize: '11px', color: '#ef4444', flex: 1 }}>{serverError}</span>
          </div>
        )}
        
        <div class="spz-card modular-card" style={{ padding: '20px', display: 'flex', flexDirection: 'column', gap: '18px' }}>
          <div>
            <label style={{ display: 'block', marginBottom: '8px', fontSize: '10px', fontFamily: 'var(--font-mono)', color: 'var(--gray-400)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>Racer Alias</label>
            <div class="input-wrapper">
              <span class="input-icon-left">
                <User size={16} color={name.length === 0 ? 'var(--gray-600)' : isValidName ? 'var(--color-primary)' : '#ef4444'} />
              </span>
              <input 
                type="text" 
                value={name}
                onInput={(e) => setName((e.target as HTMLInputElement).value)}
                placeholder="Choose alias..."
                class={`alias-input ${name.length > 0 && !isValidName ? 'invalid' : ''}`}
                maxLength={16}
              />
              {name.length > 0 && (
                <span class="input-validation-right">
                  {isValidName ? (
                    <Check size={16} color="var(--color-primary)" />
                  ) : (
                    <AlertCircle size={16} color="#ef4444" />
                  )}
                </span>
              )}
            </div>
            <div class="identity-help-text">
              {name.length === 0 ? (
                <>
                  <Sparkles size={10} color="var(--gray-600)" />
                  <span>3-16 chars (letters, numbers, underscores)</span>
                </>
              ) : !isValidName ? (
                <span style={{ color: '#ef4444' }}>Alphanumeric & underscores only</span>
              ) : (
                <span style={{ color: 'var(--color-primary)' }}>Racer alias is valid</span>
              )}
            </div>
          </div>

          <div>
            <label style={{ display: 'block', marginBottom: '8px', fontSize: '10px', fontFamily: 'var(--font-mono)', color: 'var(--gray-400)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>Model Base</label>
            <div class="gender-grid">
              <div 
                class={`gender-card ${gender === 0 ? 'active' : ''}`}
                onClick={() => setGender(0)}
              >
                <div class="gender-card-badge">
                  <Check size={10} />
                </div>
                <div class="gender-card-icon">
                  <Sparkles size={20} />
                </div>
                <span class="gender-card-label">Male Base</span>
              </div>

              <div 
                class={`gender-card ${gender === 1 ? 'active' : ''}`}
                onClick={() => setGender(1)}
              >
                <div class="gender-card-badge">
                  <Check size={10} />
                </div>
                <div class="gender-card-icon">
                  <Sparkles size={20} />
                </div>
                <span class="gender-card-label">Female Base</span>
              </div>
            </div>
          </div>
        </div>

        <div
          class="start-btn"
          onClick={isValidName && !submitting ? submitCreation : undefined}
          style={{
            width: '100%',
            display: 'flex',
            height: '44px',
            opacity: isValidName && !submitting ? 1 : 0.5,
            cursor: isValidName && !submitting ? 'pointer' : 'not-allowed',
            boxShadow: isValidName && !submitting ? undefined : 'none',
            borderColor: isValidName && !submitting ? undefined : 'var(--gray-800)'
          }}
        >
          <div
            class="start-btn-text"
            style={{
              flex: 1,
              justifyContent: 'center',
              background: isValidName && !submitting ? undefined : 'var(--gray-800)',
              color: isValidName && !submitting ? undefined : 'var(--gray-500)'
            }}
          >
            {submitting ? 'Initializing...' : 'Confirm Identity'}
          </div>
          <div class="start-btn-icon" style={{ background: isValidName && !submitting ? undefined : 'var(--gray-900)', borderColor: isValidName && !submitting ? undefined : 'var(--gray-800)', color: isValidName && !submitting ? undefined : 'var(--gray-600)' }}>
            <Play size={16} />
          </div>
        </div>
      </div>
    </div>
  );
}
