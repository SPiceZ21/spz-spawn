import { useState, useEffect, useRef } from 'preact/hooks'
import { Clock, MapPin, Play, ChevronLeft, ChevronRight, User, Sparkles, Check, AlertCircle, Fingerprint, Flag, Hash } from 'lucide-preact'

/* ISO 3166-1 alpha-2 — drives the flag shown on nametags and race standings */
const NATIONS: [string, string][] = [
  ['ar', 'Argentina'], ['au', 'Australia'], ['at', 'Austria'], ['az', 'Azerbaijan'],
  ['bh', 'Bahrain'], ['bd', 'Bangladesh'], ['be', 'Belgium'], ['br', 'Brazil'],
  ['ca', 'Canada'], ['cl', 'Chile'], ['cn', 'China'], ['co', 'Colombia'],
  ['hr', 'Croatia'], ['cz', 'Czechia'], ['dk', 'Denmark'], ['eg', 'Egypt'],
  ['ee', 'Estonia'], ['fi', 'Finland'], ['fr', 'France'], ['de', 'Germany'],
  ['gr', 'Greece'], ['hu', 'Hungary'], ['is', 'Iceland'], ['in', 'India'],
  ['id', 'Indonesia'], ['ie', 'Ireland'], ['il', 'Israel'], ['it', 'Italy'],
  ['jp', 'Japan'], ['kz', 'Kazakhstan'], ['ke', 'Kenya'], ['kw', 'Kuwait'],
  ['lv', 'Latvia'], ['lt', 'Lithuania'], ['my', 'Malaysia'], ['mx', 'Mexico'],
  ['mc', 'Monaco'], ['ma', 'Morocco'], ['np', 'Nepal'], ['nl', 'Netherlands'],
  ['nz', 'New Zealand'], ['ng', 'Nigeria'], ['no', 'Norway'], ['pk', 'Pakistan'],
  ['pe', 'Peru'], ['ph', 'Philippines'], ['pl', 'Poland'], ['pt', 'Portugal'],
  ['qa', 'Qatar'], ['ro', 'Romania'], ['sa', 'Saudi Arabia'], ['rs', 'Serbia'],
  ['sg', 'Singapore'], ['sk', 'Slovakia'], ['si', 'Slovenia'], ['za', 'South Africa'],
  ['kr', 'South Korea'], ['es', 'Spain'], ['lk', 'Sri Lanka'], ['se', 'Sweden'],
  ['ch', 'Switzerland'], ['tw', 'Taiwan'], ['th', 'Thailand'], ['tr', 'Türkiye'],
  ['ua', 'Ukraine'], ['ae', 'United Arab Emirates'], ['gb', 'United Kingdom'],
  ['us', 'United States'], ['uy', 'Uruguay'], ['vn', 'Vietnam'],
]

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
  const [cover, setCover] = useState(false)
  const [coverFading, setCoverFading] = useState(false)
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
      } else if (e.data.type === 'showCover') {
        setCoverFading(false)
        setCover(true)
      } else if (e.data.type === 'hideCover') {
        // fade out, then unmount so the menu underneath is revealed
        setCoverFading(true)
        setTimeout(() => setCover(false), 750)
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

  const licenseClass = player.licenseClass || 'D'

  return (
    <>
      {cover && <Cover fading={coverFading} />}

      {view === 'creation' && (
        <CharacterCreation serverError={creationError} onClearError={() => setCreationError(null)} />
      )}

      {view === 'spawn' && (<>
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
      </>)}
    </>
  )
}

/* Full-screen branded cover — bridges the loading screen and the spawn menu so
   the raw world streaming / ped placement is never visible. */
function Cover({ fading }: { fading: boolean }) {
  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 99999,
        background:
          'radial-gradient(130% 90% at 50% 0%, rgba(255,102,0,0.12), transparent 55%), radial-gradient(100% 100% at 50% 120%, rgba(255,102,0,0.06), transparent 60%), #08090b',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        opacity: fading ? 0 : 1,
        transition: 'opacity 700ms ease',
        pointerEvents: fading ? 'none' : 'auto',
        fontFamily: "'Inter', sans-serif",
      }}
    >
      <style>{`
        @keyframes spzpulse{0%,100%{opacity:.85}50%{opacity:.35}}
        @keyframes spzrise{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:none}}
        @keyframes spzblob{0%,100%{border-radius:42% 58% 60% 40% / 45% 45% 55% 55%}25%{border-radius:60% 40% 45% 55% / 55% 60% 40% 45%}50%{border-radius:45% 55% 48% 52% / 60% 45% 55% 40%}75%{border-radius:55% 45% 55% 45% / 42% 55% 45% 58%}}
        @keyframes spzblobspin{to{transform:rotate(360deg)}}
        @keyframes spzglow{0%,100%{box-shadow:0 0 40px 6px rgba(255,102,0,0.45),inset 0 -8px 20px rgba(120,40,0,0.5)}50%{box-shadow:0 0 66px 16px rgba(255,102,0,0.72),inset 0 -8px 20px rgba(120,40,0,0.5)}}
      `}</style>

      {/* faint grid / scanline texture */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          backgroundImage:
            'repeating-linear-gradient(0deg, rgba(255,255,255,0.015) 0px, rgba(255,255,255,0.015) 1px, transparent 1px, transparent 3px)',
          pointerEvents: 'none',
        }}
      />

      {/* morphing blob loader */}
      <div style={{ position: 'relative', width: '96px', height: '96px', marginBottom: '38px', zIndex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <div
          style={{
            width: '82px',
            height: '82px',
            background: 'radial-gradient(circle at 34% 28%, #ffcf9c, #ff6600 50%, #a63a00 100%)',
            borderRadius: '42% 58% 60% 40% / 45% 45% 55% 55%',
            animation: 'spzblob 6s ease-in-out infinite, spzblobspin 14s linear infinite, spzglow 2.4s ease-in-out infinite',
          }}
        />
      </div>

      {/* logo + tagline */}
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '14px', animation: 'spzrise .5s ease', zIndex: 1 }}>
        <img
          src="logo.png"
          alt="SPiceZ"
          style={{ height: '58px', width: 'auto', filter: 'drop-shadow(0 8px 40px rgba(255,102,0,0.3))' }}
        />
        <div
          style={{
            fontFamily: 'monospace',
            fontSize: '10px',
            letterSpacing: '0.42em',
            textTransform: 'uppercase',
            color: 'rgba(255,255,255,0.35)',
          }}
        >
          Open-Source Racing Core
        </div>
      </div>

      <div
        style={{
          marginTop: '34px',
          fontFamily: 'monospace',
          fontSize: '11px',
          letterSpacing: '0.26em',
          textTransform: 'uppercase',
          color: 'rgba(255,255,255,0.42)',
          animation: 'spzpulse 1.8s ease-in-out infinite',
          zIndex: 1,
        }}
      >
        Preparing your session
      </div>

      {/* bottom brand strip */}
      <div
        style={{
          position: 'absolute',
          bottom: '28px',
          left: '50%',
          transform: 'translateX(-50%)',
          display: 'flex',
          alignItems: 'center',
          gap: '9px',
          zIndex: 1,
        }}
      >
        <span style={{ width: '6px', height: '6px', borderRadius: '50%', background: '#ff6600', boxShadow: '0 0 9px #ff6600' }} />
        <span
          style={{
            fontFamily: 'monospace',
            fontSize: '9px',
            letterSpacing: '0.3em',
            textTransform: 'uppercase',
            color: 'rgba(255,255,255,0.28)',
          }}
        >
          SPiceZ-Core · FiveM
        </span>
      </div>
    </div>
  )
}

function CharacterCreation({ serverError, onClearError }: { serverError: string | null, onClearError: () => void }) {
  const [name, setName] = useState('');
  const [gender, setGender] = useState(0);
  const [nation, setNation] = useState('');
  const [raceNumber, setRaceNumber] = useState('');
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (serverError) setSubmitting(false);
  }, [serverError]);

  const isValidName = /^[a-zA-Z0-9_]{3,16}$/.test(name);
  const numValue = parseInt(raceNumber, 10);
  const isValidNumber = !isNaN(numValue) && numValue >= 1 && numValue <= 99;
  const canSubmit = isValidName && nation !== '' && isValidNumber && !submitting;

  const submitCreation = () => {
    if (!canSubmit) return;
    setSubmitting(true);
    onClearError();
    fetch(`https://${GetParentResourceName()}/submitCharacterCreation`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, gender, nation, raceNumber: numValue }),
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

          <div style={{ display: 'flex', gap: '12px' }}>
            <div style={{ flex: 1, minWidth: 0 }}>
              <label style={{ display: 'block', marginBottom: '8px', fontSize: '10px', fontFamily: 'var(--font-mono)', color: 'var(--gray-400)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>Nation</label>
              <div class="input-wrapper">
                <span class="input-icon-left">
                  {nation
                    ? <img src={`flags/${nation}.webp`} style={{ height: '12px', borderRadius: '2px' }} />
                    : <Flag size={16} color="var(--gray-600)" />}
                </span>
                <select
                  class="alias-input"
                  value={nation}
                  onChange={(e) => setNation((e.target as HTMLSelectElement).value)}
                  style={{ appearance: 'none', cursor: 'pointer', color: nation ? undefined : 'var(--gray-500)' }}
                >
                  <option value="" disabled>Select nation...</option>
                  {NATIONS.map(([code, label]) => (
                    <option key={code} value={code}>{label}</option>
                  ))}
                </select>
              </div>
            </div>

            <div style={{ width: '130px', flexShrink: 0 }}>
              <label style={{ display: 'block', marginBottom: '8px', fontSize: '10px', fontFamily: 'var(--font-mono)', color: 'var(--gray-400)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>Race Number</label>
              <div class="input-wrapper">
                <span class="input-icon-left">
                  <Hash size={16} color={raceNumber.length === 0 ? 'var(--gray-600)' : isValidNumber ? 'var(--color-primary)' : '#ef4444'} />
                </span>
                <input
                  type="text"
                  inputMode="numeric"
                  value={raceNumber}
                  onInput={(e) => setRaceNumber((e.target as HTMLInputElement).value.replace(/\D/g, '').slice(0, 2))}
                  placeholder="1-99"
                  class={`alias-input ${raceNumber.length > 0 && !isValidNumber ? 'invalid' : ''}`}
                  maxLength={2}
                />
              </div>
            </div>
          </div>
        </div>

        <div
          class="start-btn"
          onClick={canSubmit ? submitCreation : undefined}
          style={{
            width: '100%',
            display: 'flex',
            height: '44px',
            opacity: canSubmit ? 1 : 0.5,
            cursor: canSubmit ? 'pointer' : 'not-allowed',
            boxShadow: canSubmit ? undefined : 'none',
            borderColor: canSubmit ? undefined : 'var(--gray-800)'
          }}
        >
          <div
            class="start-btn-text"
            style={{
              flex: 1,
              justifyContent: 'center',
              background: canSubmit ? undefined : 'var(--gray-800)',
              color: canSubmit ? undefined : 'var(--gray-500)'
            }}
          >
            {submitting ? 'Initializing...' : 'Confirm Identity'}
          </div>
          <div class="start-btn-icon" style={{ background: canSubmit ? undefined : 'var(--gray-900)', borderColor: canSubmit ? undefined : 'var(--gray-800)', color: canSubmit ? undefined : 'var(--gray-600)' }}>
            <Play size={16} />
          </div>
        </div>
      </div>
    </div>
  );
}
